-- Keep a decline visible only to the person who chose it. The shared consent
-- row remains requested, so the initiator learns nothing beyond "waiting."
create table public.insight_declines (
  insight_id uuid not null
    references public.insights(id) on delete cascade,
  profile_id uuid not null
    references public.profiles(id) on delete cascade,
  declined_at timestamptz not null default now(),
  primary key (insight_id, profile_id)
);

alter table public.insight_declines enable row level security;

create policy insight_declines_select_own
  on public.insight_declines
  for select
  to authenticated
  using (profile_id = (select auth.uid()));

grant select on public.insight_declines to authenticated;
alter publication supabase_realtime add table public.insight_declines;

create or replace function public.request_reveal(p_insight uuid)
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

  if c.resolution_type is not null then
    raise exception 'already resolved';
  end if;
  if c.readiness not in ('idle', 'withdrawn') then
    raise exception 'reveal already in motion';
  end if;
  if c.visibility = 'private'
     and c.owner_id <> (select auth.uid()) then
    raise exception 'not your private item';
  end if;

  delete from public.insight_declines
  where insight_id = p_insight;

  update public.insight_consent
  set visibility = case
        when visibility = 'mutual' then 'mutual'
        else 'shared'
      end,
      owner_id = null,
      readiness = 'requested',
      initiator_id = (select auth.uid()),
      requested_at = now(),
      accepted_at = null
  where insight_id = p_insight;
end;
$$;

create or replace function public.accept_reveal(p_insight uuid)
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
    raise exception 'nothing to accept';
  end if;
  if c.initiator_id = (select auth.uid()) then
    raise exception 'cannot accept your own request';
  end if;

  delete from public.insight_declines
  where insight_id = p_insight
    and profile_id = (select auth.uid());

  update public.insight_consent
  set readiness = 'accepted',
      visibility = 'mutual',
      accepted_at = now()
  where insight_id = p_insight;
end;
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

  insert into public.insight_declines (insight_id, profile_id)
  values (p_insight, (select auth.uid()))
  on conflict (insight_id, profile_id)
  do update set declined_at = now();
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

  delete from public.insight_declines
  where insight_id = p_insight;

  update public.insight_consent
  set readiness = 'idle',
      initiator_id = null,
      requested_at = null,
      accepted_at = null
  where insight_id = p_insight;
end;
$$;

-- Shared-item writes and account deletion take this transaction-scoped lock
-- before touching relationship rows. This gives every path the same lock
-- order and avoids an UPDATE-versus-deletion deadlock.
create or replace function private.lock_relationship(p_couple uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_couple is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(p_couple::text, 0)
    );
  end if;
end;
$$;

create or replace function public.create_plan(
  p_couple uuid,
  p_title text,
  p_note text default null,
  p_scheduled_on date default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if p_couple is null
     or p_couple <> (select public.my_couple_id()) then
    raise exception 'not your active WE space';
  end if;
  perform private.lock_relationship(p_couple);
  insert into public.plans (
    couple_id, title, note, scheduled_on
  ) values (
    p_couple, trim(p_title), p_note, p_scheduled_on
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.update_plan(
  p_id uuid,
  p_title text,
  p_note text default null,
  p_scheduled_on date default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid;
begin
  select p.couple_id into v_couple
  from public.plans p
  where p.id = p_id
    and p.couple_id = (select public.my_couple_id());
  if v_couple is null then
    raise exception 'not your active WE space';
  end if;
  perform private.lock_relationship(v_couple);
  update public.plans
  set title = trim(p_title),
      note = p_note,
      scheduled_on = p_scheduled_on
  where id = p_id
    and couple_id = v_couple;
  if not found then
    raise exception 'shared plan no longer exists';
  end if;
end;
$$;

create or replace function public.set_plan_status(
  p_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid;
begin
  select p.couple_id into v_couple
  from public.plans p
  where p.id = p_id
    and p.couple_id = (select public.my_couple_id());
  if v_couple is null then
    raise exception 'not your active WE space';
  end if;
  perform private.lock_relationship(v_couple);
  update public.plans
  set status = p_status
  where id = p_id
    and couple_id = v_couple;
  if not found then
    raise exception 'shared plan no longer exists';
  end if;
end;
$$;

create or replace function public.create_responsibility(
  p_couple uuid,
  p_title text,
  p_note text default null,
  p_owner uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if p_couple is null
     or p_couple <> (select public.my_couple_id()) then
    raise exception 'not your active WE space';
  end if;
  perform private.lock_relationship(p_couple);
  insert into public.responsibilities (
    couple_id, title, note, owner_id
  ) values (
    p_couple, trim(p_title), p_note, p_owner
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.update_responsibility(
  p_id uuid,
  p_title text,
  p_note text default null,
  p_owner uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid;
begin
  select r.couple_id into v_couple
  from public.responsibilities r
  where r.id = p_id
    and r.couple_id = (select public.my_couple_id());
  if v_couple is null then
    raise exception 'not your active WE space';
  end if;
  perform private.lock_relationship(v_couple);
  update public.responsibilities
  set title = trim(p_title),
      note = p_note,
      owner_id = p_owner
  where id = p_id
    and couple_id = v_couple;
  if not found then
    raise exception 'shared responsibility no longer exists';
  end if;
end;
$$;

create or replace function public.set_responsibility_status(
  p_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid;
begin
  select r.couple_id into v_couple
  from public.responsibilities r
  where r.id = p_id
    and r.couple_id = (select public.my_couple_id());
  if v_couple is null then
    raise exception 'not your active WE space';
  end if;
  perform private.lock_relationship(v_couple);
  update public.responsibilities
  set status = p_status
  where id = p_id
    and couple_id = v_couple;
  if not found then
    raise exception 'shared responsibility no longer exists';
  end if;
end;
$$;

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid := (select public.my_couple_id());
begin
  perform private.lock_relationship(v_couple);
  perform private.delete_my_account();
end;
$$;

revoke insert, update, delete on public.plans from authenticated;
revoke insert, update, delete on public.responsibilities from authenticated;

revoke all on function private.lock_relationship(uuid)
  from public, anon, authenticated;

revoke all on function public.create_plan(uuid,text,text,date)
  from public, anon;
revoke all on function public.update_plan(uuid,text,text,date)
  from public, anon;
revoke all on function public.set_plan_status(uuid,text)
  from public, anon;
revoke all on function public.create_responsibility(uuid,text,text,uuid)
  from public, anon;
revoke all on function public.update_responsibility(uuid,text,text,uuid)
  from public, anon;
revoke all on function public.set_responsibility_status(uuid,text)
  from public, anon;

grant execute on function public.create_plan(uuid,text,text,date)
  to authenticated;
grant execute on function public.update_plan(uuid,text,text,date)
  to authenticated;
grant execute on function public.set_plan_status(uuid,text)
  to authenticated;
grant execute on function public.create_responsibility(uuid,text,text,uuid)
  to authenticated;
grant execute on function public.update_responsibility(uuid,text,text,uuid)
  to authenticated;
grant execute on function public.set_responsibility_status(uuid,text)
  to authenticated;
