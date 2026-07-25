-- Close the remaining trust-boundary races and keep private consent state
-- private at the database boundary, not only in the native projection.

do $$
begin
  if exists (
    select 1
    from public.couple_members
    group by profile_id
    having count(*) > 1
  ) then
    raise exception 'A profile already belongs to more than one WE space';
  end if;
end;
$$;

drop index if exists public.couple_members_profile_id_idx;
alter table public.couple_members
  add constraint couple_members_profile_id_key unique (profile_id);

alter table public.profiles
  add constraint profiles_name_length_check
  check (char_length(trim(name)) between 1 and 100) not valid;
alter table public.responses
  add constraint responses_choice_length_check
  check (choice is null or char_length(choice) between 1 and 160) not valid,
  add constraint responses_note_length_check
  check (note is null or char_length(note) <= 2000) not valid;
alter table public.reflections
  add constraint reflections_text_length_check
  check (char_length(trim(text)) between 1 and 4000) not valid;
alter table public.insight_consent
  add constraint insight_consent_resolution_choice_length_check
  check (
    resolution_choice is null
    or char_length(resolution_choice) <= 160
  ) not valid;

alter table public.profiles validate constraint profiles_name_length_check;
alter table public.responses
  validate constraint responses_choice_length_check;
alter table public.responses validate constraint responses_note_length_check;
alter table public.reflections
  validate constraint reflections_text_length_check;
alter table public.insight_consent
  validate constraint insight_consent_resolution_choice_length_check;

create index reflections_owner_created_idx
  on public.reflections(owner_id, created_at);
create index plans_couple_scheduled_idx
  on public.plans(couple_id, scheduled_on);
create index responsibilities_couple_created_idx
  on public.responsibilities(couple_id, created_at);

create or replace function private.prepare_shared_item()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
begin
  if v_user is null or new.couple_id <> (select public.my_couple_id()) then
    raise exception 'not your active WE space';
  end if;

  -- Account deletion takes FOR UPDATE on this same relationship row.
  -- Mutations already in flight finish first; later ones wait and then fail.
  perform 1
  from public.couples c
  where c.id = new.couple_id
  for key share;
  if not found then
    raise exception 'not your active WE space';
  end if;

  if tg_table_name = 'responsibilities'
     and new.owner_id is not null
     and not exists (
       select 1
       from public.couple_members cm
       where cm.couple_id = new.couple_id
         and cm.profile_id = new.owner_id
     ) then
    raise exception 'responsibility owner is not in this WE space';
  end if;

  if tg_op = 'INSERT' then
    new.created_by := v_user;
    new.created_at := now();
  else
    if new.couple_id <> old.couple_id then
      raise exception 'a shared item cannot move between WE spaces';
    end if;
    new.created_by := old.created_by;
    new.created_at := old.created_at;
  end if;

  new.updated_by := v_user;
  new.updated_at := now();
  if new.status = 'completed' and new.completed_at is null then
    new.completed_at := now();
  elsif new.status = 'active' then
    new.completed_at := null;
  end if;
  return new;
end;
$$;

create or replace function public.assert_my_insight(p_insight uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_couple uuid;
begin
  select i.couple_id
  into v_couple
  from public.insights i
  where i.id = p_insight;

  if v_couple is null
     or v_couple <> (select public.my_couple_id()) then
    raise exception 'not your insight';
  end if;

  perform 1
  from public.couples c
  where c.id = v_couple
  for key share;
  if not found then
    raise exception 'not your insight';
  end if;

  return v_couple;
end;
$$;

create or replace function public.can_read_insight(p_insight uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.insights i
    join public.insight_consent ic on ic.insight_id = i.id
    where i.id = p_insight
      and i.couple_id = (select public.my_couple_id())
      and (
        ic.visibility <> 'private'
        or ic.owner_id = (select auth.uid())
      )
  );
$$;

drop policy if exists insights_select on public.insights;
create policy insights_select on public.insights for select to authenticated
  using ((select public.can_read_insight(id)));

drop policy if exists insight_consent_select on public.insight_consent;
create policy insight_consent_select on public.insight_consent
  for select to authenticated
  using ((select public.can_read_insight(insight_id)));

revoke execute on function public.can_read_insight(uuid)
  from public, anon;
grant execute on function public.can_read_insight(uuid) to authenticated;

create or replace function public.gen_join_code()
returns text
language sql
volatile
security definer
set search_path = ''
as $$
  select upper(encode(extensions.gen_random_bytes(8), 'hex'));
$$;

create or replace function public.decline_reveal(p_insight uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.insight_consent;
begin
  perform public.assert_my_insight(p_insight);
  select * into c
  from public.insight_consent
  where insight_id = p_insight
  for update;

  if c.readiness <> 'requested' then
    raise exception 'nothing to decline';
  end if;
  if c.initiator_id = (select auth.uid()) then
    raise exception 'cannot decline your own request';
  end if;

  -- Deliberately leave the shared request unchanged. "Not now" is private,
  -- and the initiator continues to see only that their invitation is waiting.
end;
$$;

create or replace function public.withdraw_reveal(p_insight uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.insight_consent;
begin
  perform public.assert_my_insight(p_insight);
  select * into c
  from public.insight_consent
  where insight_id = p_insight
  for update;

  if c.readiness not in ('requested', 'declined') then
    raise exception 'nothing to withdraw';
  end if;
  if c.initiator_id <> (select auth.uid()) then
    raise exception 'only the initiator can withdraw';
  end if;

  update public.insight_consent
  set readiness = 'idle',
      initiator_id = null,
      requested_at = null,
      accepted_at = null
  where insight_id = p_insight;
end;
$$;

create or replace function public.submit_response(
  p_insight uuid,
  p_choice text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.insight_consent;
  v_couple uuid;
  v_partner uuid;
  v_my text;
  v_ptr text;
begin
  v_couple := public.assert_my_insight(p_insight);
  select * into c
  from public.insight_consent
  where insight_id = p_insight
  for update;

  if c.visibility <> 'mutual' then
    raise exception 'answers happen only once opened together';
  end if;
  if not exists (
    select 1
    from public.insights i
    where i.id = p_insight
      and p_choice = any(i.options)
  ) then
    raise exception 'answer is not one of this insight''s options';
  end if;

  select status into v_my
  from public.responses
  where insight_id = p_insight
    and profile_id = (select auth.uid());
  if v_my in ('submitted', 'revealed') then
    raise exception 'already submitted';
  end if;

  insert into public.responses (
    insight_id, profile_id, status, choice, note, updated_at
  ) values (
    p_insight, (select auth.uid()), 'submitted', p_choice, p_note, now()
  )
  on conflict (insight_id, profile_id)
  do update
    set status = 'submitted',
        choice = excluded.choice,
        note = excluded.note,
        updated_at = now();

  v_partner := public.partner_id(v_couple);
  select status into v_ptr
  from public.responses
  where insight_id = p_insight
    and profile_id = v_partner;
  if v_ptr = 'submitted' then
    update public.responses
    set status = 'revealed',
        updated_at = now()
    where insight_id = p_insight
      and profile_id in ((select auth.uid()), v_partner);
  end if;
end;
$$;

create or replace function public.resolve_insight(
  p_insight uuid,
  p_type text,
  p_choice text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.insight_consent;
  v_revealed integer;
begin
  perform public.assert_my_insight(p_insight);
  select * into c
  from public.insight_consent
  where insight_id = p_insight
  for update;

  if c.resolution_type is not null then
    raise exception 'already resolved';
  end if;
  if p_type not in ('settled', 'released', 'leftOpen') then
    raise exception 'bad resolution';
  end if;

  select count(*) into v_revealed
  from public.responses
  where insight_id = p_insight
    and status = 'revealed';
  if v_revealed < 2 then
    raise exception 'cannot resolve before both answers are revealed';
  end if;

  update public.insight_consent
  set resolution_type = p_type,
      resolution_choice = p_choice,
      resolved_at = now()
  where insight_id = p_insight;
end;
$$;

create or replace function private.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_couple uuid;
  v_survivor uuid;
  v_ended timestamptz := now();
  v_snapshot jsonb;
begin
  if v_user is null then
    raise exception 'not signed in';
  end if;

  select cm.couple_id
  into v_couple
  from public.couple_members cm
  where cm.profile_id = v_user
  limit 1;

  if v_couple is not null then
    select c.id
    into v_couple
    from public.couples c
    where c.id = v_couple
    for update;
  end if;

  if v_couple is not null then
    -- Lock shared state in the same order used by trust mutations. Anything
    -- already in flight commits before the snapshot; anything later waits
    -- for the relationship deletion and then fails cleanly.
    perform 1
    from public.insight_consent ic
    join public.insights i on i.id = ic.insight_id
    where i.couple_id = v_couple
    for update of ic;

    perform 1
    from public.responses r
    join public.insights i on i.id = r.insight_id
    where i.couple_id = v_couple
    for update of r;

    perform 1
    from public.dismissals d
    join public.insights i on i.id = d.insight_id
    where i.couple_id = v_couple
    for update of d;

    perform 1 from public.insights
    where couple_id = v_couple
    for update;
    perform 1 from public.plans
    where couple_id = v_couple
    for update;
    perform 1 from public.responsibilities
    where couple_id = v_couple
    for update;
    perform 1 from public.reflections
    where couple_id = v_couple
    for update;
    perform 1 from public.couple_members
    where couple_id = v_couple
    for update;

    select cm.profile_id
    into v_survivor
    from public.couple_members cm
    where cm.couple_id = v_couple
      and cm.profile_id <> v_user
    limit 1;

    if v_survivor is not null then
      v_snapshot := jsonb_build_object(
        'plans', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', p.id,
            'title', p.title,
            'note', p.note,
            'scheduledOn', p.scheduled_on,
            'status', p.status,
            'completedAt', p.completed_at,
            'updatedAt', p.updated_at
          ) order by p.created_at)
          from public.plans p
          where p.couple_id = v_couple
        ), '[]'::jsonb),
        'responsibilities', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', r.id,
            'title', r.title,
            'note', r.note,
            'ownership', case
              when r.owner_id is null then 'together'
              when r.owner_id = v_survivor then 'me'
              else 'partner'
            end,
            'status', r.status,
            'completedAt', r.completed_at,
            'updatedAt', r.updated_at
          ) order by r.created_at)
          from public.responsibilities r
          where r.couple_id = v_couple
        ), '[]'::jsonb),
        'resolutions', coalesce((
          select jsonb_agg(jsonb_build_object(
            'insightID', i.id,
            'title', i.title,
            'resolutionType', ic.resolution_type,
            'resolutionChoice', ic.resolution_choice,
            'resolvedAt', ic.resolved_at
          ) order by ic.resolved_at)
          from public.insights i
          join public.insight_consent ic on ic.insight_id = i.id
          where i.couple_id = v_couple
            and ic.resolution_type is not null
        ), '[]'::jsonb)
      );

      insert into public.relationship_archives (
        owner_id, ended_at, snapshot_version, snapshot
      ) values (v_survivor, v_ended, 1, v_snapshot);
    end if;

    delete from public.couples where id = v_couple;
  end if;

  delete from auth.users where id = v_user;
end;
$$;

revoke execute on function public.gen_join_code()
  from public, anon, authenticated;
revoke execute on function private.delete_my_account()
  from public, anon, authenticated;
