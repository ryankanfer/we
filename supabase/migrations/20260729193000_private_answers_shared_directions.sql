-- Answers are permanently owner-only. The only shared result is a
-- server-produced direction whose wording comes from a small, reviewed set.
-- Soft Start proposals remain independent of couple membership until their
-- owner deliberately offers the exact preview they approved.

begin;

create table public.shared_directions (
  insight_id uuid primary key
    references public.insights(id) on delete cascade,
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  direction_key text not null
    check (char_length(direction_key) between 1 and 40),
  eyebrow text not null
    check (char_length(eyebrow) between 1 and 40),
  title text not null
    check (char_length(title) between 1 and 120),
  message text not null
    check (char_length(message) between 1 and 240),
  symbol text not null
    check (char_length(symbol) between 1 and 60),
  created_at timestamptz not null default now()
);

create index shared_directions_couple_idx
  on public.shared_directions(couple_id);

create table public.private_proposals (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null
    references public.profiles(id) on delete cascade,
  local_id uuid not null,
  source_note text not null
    check (char_length(source_note) between 1 and 2000),
  proposal_title text not null
    check (char_length(proposal_title) between 1 and 120),
  offered_title text not null
    check (char_length(offered_title) between 1 and 120),
  offered_question text not null
    check (char_length(offered_question) between 1 and 180),
  offered_options text[] not null
    check (
      cardinality(offered_options) between 2 and 5
      and array_position(offered_options, null) is null
    ),
  preparation_method text not null
    check (
      preparation_method in (
        'onDeviceModel',
        'deterministicFallback'
      )
    ),
  prepared_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, local_id)
);

create table public.offered_topics (
  id uuid primary key default gen_random_uuid(),
  private_proposal_id uuid not null unique
    references public.private_proposals(id) on delete cascade,
  owner_id uuid not null
    references public.profiles(id) on delete cascade,
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  title text not null
    check (char_length(title) between 1 and 120),
  question text not null
    check (char_length(question) between 1 and 180),
  options text[] not null
    check (
      cardinality(options) between 2 and 5
      and array_position(options, null) is null
    ),
  offered_at timestamptz not null default now()
);

create index offered_topics_couple_idx
  on public.offered_topics(couple_id, offered_at desc);

alter table public.shared_directions enable row level security;
alter table public.private_proposals enable row level security;
alter table public.offered_topics enable row level security;

create policy shared_directions_select
  on public.shared_directions
  for select
  to authenticated
  using (
    couple_id = (select public.my_couple_id())
    and (select public.can_read_insight(insight_id))
  );

create policy private_proposals_select_own
  on public.private_proposals
  for select
  to authenticated
  using (owner_id = (select auth.uid()));

create policy offered_topics_select_approved
  on public.offered_topics
  for select
  to authenticated
  using (
    owner_id = (select auth.uid())
    or couple_id = (select public.my_couple_id())
  );

grant select on public.shared_directions to authenticated;
grant select on public.private_proposals to authenticated;
grant select on public.offered_topics to authenticated;

-- This helper can inspect private rows, but its result is selected only from
-- fixed product copy. It never returns a choice, note, match flag, or excerpt.
create or replace function private.shared_direction_values(
  p_insight uuid
)
returns table (
  direction_key text,
  eyebrow text,
  title text,
  message text,
  symbol text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_seed text;
begin
  select i.seed_key
  into v_seed
  from public.insights i
  where i.id = p_insight;

  eyebrow := case
    when v_seed like 'tonight-%' then 'FOR TONIGHT'
    when v_seed like 'weekend-%' then 'FOR THE WEEKEND'
    when v_seed like 'load-%' then 'FOR THIS WEEK'
    when v_seed like 'plan-%' then 'FOR THE PLAN'
    else 'BETWEEN YOU'
  end;

  -- A shared direction may vary only with public insight context. If it varied
  -- with choice content or answer equality, a person could infer their
  -- partner's answer by comparing the result with their own.
  if v_seed like 'tonight-%' then
    direction_key := 'evening-room';
    title := 'Begin with a little room';
    message :=
      'Keep the first part unhurried, with room to change course.';
    symbol := 'sun.horizon';
  elsif v_seed like 'weekend-%' then
    direction_key := 'open-weekend';
    title := 'Leave part of it open';
    message :=
      'Choose one easy beginning without deciding the whole weekend.';
    symbol := 'water.waves';
  elsif v_seed like 'load-%' then
    direction_key := 'lighter-week';
    title := 'Make one thing lighter';
    message :=
      'Choose the smallest shared adjustment and let the rest wait.';
    symbol := 'line.horizontal.3.decrease';
  elsif v_seed like 'plan-%' then
    direction_key := 'protected-beginning';
    title := 'Protect the simplest beginning';
    message :=
      'Name one quality to carry into the plan without deciding every detail.';
    symbol := 'sparkle';
  else
    direction_key := 'shared-room';
    title := 'Start with a little room';
    message :=
      'Choose one easy beginning without deciding the whole shape.';
    symbol := 'line.horizontal.3.decrease';
  end if;

  return next;
end;
$$;

-- Backfill a safe result for every completed legacy exchange before removing
-- the former revealed state.
insert into public.shared_directions (
  insight_id,
  couple_id,
  direction_key,
  eyebrow,
  title,
  message,
  symbol,
  created_at
)
select
  i.id,
  i.couple_id,
  d.direction_key,
  d.eyebrow,
  d.title,
  d.message,
  d.symbol,
  coalesce(ic.resolved_at, now())
from public.insights i
join public.insight_consent ic on ic.insight_id = i.id
cross join lateral private.shared_direction_values(i.id) d
where ic.resolution_type is not null
   or (
     select count(*)
     from public.responses r
     where r.insight_id = i.id
       and r.status in ('submitted', 'revealed')
   ) >= 2
on conflict (insight_id) do nothing;

-- A legacy resolution may contain one person's exact answer. Replace it with
-- the reviewed direction title before any new client can request the row.
update public.insight_consent ic
set resolution_choice = case
      when ic.resolution_type = 'settled' then sd.title
      else null
    end
from public.shared_directions sd
where sd.insight_id = ic.insight_id
  and ic.resolution_type is not null;

-- Existing archive JSON is also a shared-result interface. Keep its shape for
-- older clients while removing any historical answer-derived wording.
update public.relationship_archives ra
set snapshot = jsonb_set(
  ra.snapshot,
  '{resolutions}',
  coalesce(
    (
      select jsonb_agg(
        (entry.value - 'resolutionChoice')
        || jsonb_build_object(
          'resolutionChoice',
          case
            when entry.value->>'resolutionType' = 'settled'
              then 'A shared direction'
            else null
          end
        )
        order by entry.ordinality
      )
      from jsonb_array_elements(
        coalesce(ra.snapshot->'resolutions', '[]'::jsonb)
      ) with ordinality as entry(value, ordinality)
    ),
    '[]'::jsonb
  ),
  true
)
where ra.snapshot ? 'resolutions';

-- Plan approaches are private intentions, not a second answer-reveal system.
-- Remove historical copies from survivor archives before any client decodes
-- them, and make every future archive discard the legacy field.
update public.relationship_archives
set snapshot = snapshot - 'approaches'
where snapshot ? 'approaches';

create or replace function private.remove_private_archive_approaches()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.snapshot := new.snapshot - 'approaches';
  return new;
end;
$$;

drop trigger if exists zz_relationship_archives_remove_private_approaches
  on public.relationship_archives;
create trigger zz_relationship_archives_remove_private_approaches
before insert on public.relationship_archives
for each row
execute function private.remove_private_archive_approaches();

update public.responses
set status = 'submitted',
    updated_at = now()
where status = 'revealed';

alter table public.responses
  drop constraint if exists responses_status_check;
alter table public.responses
  add constraint responses_status_check
  check (status in ('none', 'draft', 'submitted'))
  not valid;
alter table public.responses
  validate constraint responses_status_check;

drop policy if exists responses_select on public.responses;
drop policy if exists responses_select_own on public.responses;
create policy responses_select_own
  on public.responses
  for select
  to authenticated
  using (profile_id = (select auth.uid()));

update public.plan_approaches
set revealed_at = null
where revealed_at is not null;

alter table public.plan_approaches
  drop constraint if exists plan_approaches_never_revealed_check;
alter table public.plan_approaches
  add constraint plan_approaches_never_revealed_check
  check (revealed_at is null)
  not valid;
alter table public.plan_approaches
  validate constraint plan_approaches_never_revealed_check;

drop policy if exists plan_approaches_select
  on public.plan_approaches;
create policy plan_approaches_select
  on public.plan_approaches
  for select
  to authenticated
  using (profile_id = (select auth.uid()));

create or replace function public.set_plan_approach(
  p_plan uuid,
  p_approach text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid;
  v_user uuid := (select auth.uid());
begin
  select p.couple_id into v_couple
  from public.plans p
  where p.id = p_plan
    and p.couple_id = (select public.my_couple_id());
  perform private.assert_v2_member(v_couple);
  if p_approach not in ('gently', 'directly', 'together') then
    raise exception 'unknown approach';
  end if;

  insert into public.plan_approaches (
    plan_id,
    couple_id,
    profile_id,
    approach,
    note,
    revealed_at
  ) values (
    p_plan,
    v_couple,
    v_user,
    p_approach,
    p_note,
    null
  )
  on conflict (plan_id, profile_id) do update
  set approach = excluded.approach,
      note = excluded.note,
      revealed_at = null,
      created_at = now();
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
  v_my text;
  v_submitted integer;
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

  select r.status
  into v_my
  from public.responses r
  where r.insight_id = p_insight
    and r.profile_id = (select auth.uid());
  if v_my = 'submitted' then
    raise exception 'already submitted';
  end if;

  insert into public.responses (
    insight_id,
    profile_id,
    status,
    choice,
    note,
    updated_at
  ) values (
    p_insight,
    (select auth.uid()),
    'submitted',
    p_choice,
    p_note,
    now()
  )
  on conflict (insight_id, profile_id)
  do update
    set status = 'submitted',
        choice = excluded.choice,
        note = excluded.note,
        updated_at = now();

  select count(*)::integer
  into v_submitted
  from public.responses r
  where r.insight_id = p_insight
    and r.status = 'submitted';

  if v_submitted >= 2 then
    insert into public.shared_directions (
      insight_id,
      couple_id,
      direction_key,
      eyebrow,
      title,
      message,
      symbol
    )
    select
      p_insight,
      v_couple,
      d.direction_key,
      d.eyebrow,
      d.title,
      d.message,
      d.symbol
    from private.shared_direction_values(p_insight) d
    on conflict (insight_id) do nothing;
  end if;
end;
$$;

create or replace function public.partner_answer_statuses()
returns table (
  insight_id uuid,
  profile_id uuid,
  has_answered boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    r.insight_id,
    r.profile_id,
    true
  from public.responses r
  join public.insights i on i.id = r.insight_id
  where i.couple_id = (select public.my_couple_id())
    and r.profile_id <> (select auth.uid())
    and r.status = 'submitted'
    and public.can_read_insight(i.id);
$$;

-- Keep the old three-argument RPC boundary for deployed clients, but never
-- trust or persist p_choice. A completed resolution references only the safe
-- shared direction.
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
  v_direction public.shared_directions;
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

  select * into v_direction
  from public.shared_directions sd
  where sd.insight_id = p_insight;
  if v_direction.insight_id is null then
    raise exception 'cannot resolve before a shared direction exists';
  end if;

  update public.insight_consent
  set resolution_type = p_type,
      resolution_choice = case
        when p_type = 'settled' then v_direction.title
        else null
      end,
      resolved_at = now()
  where insight_id = p_insight;
end;
$$;

create or replace function public.claim_private_proposal(
  p_local_id uuid,
  p_source_note text,
  p_title text,
  p_offered_title text,
  p_offered_question text,
  p_offered_options text[],
  p_preparation_method text,
  p_created_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_proposal uuid;
begin
  if v_user is null then
    raise exception 'not signed in';
  end if;
  if nullif(btrim(p_source_note), '') is null
     or char_length(p_source_note) > 2000
     or nullif(btrim(p_title), '') is null
     or char_length(p_title) > 120
     or nullif(btrim(p_offered_title), '') is null
     or char_length(p_offered_title) > 120
     or nullif(btrim(p_offered_question), '') is null
     or char_length(p_offered_question) > 180
     or cardinality(p_offered_options) not between 2 and 5
     or exists (
       select 1
       from unnest(p_offered_options) option_value
       where nullif(btrim(option_value), '') is null
          or char_length(option_value) > 80
     )
     or p_preparation_method not in (
       'onDeviceModel',
       'deterministicFallback'
     ) then
    raise exception 'invalid private proposal';
  end if;

  insert into public.private_proposals (
    owner_id,
    local_id,
    source_note,
    proposal_title,
    offered_title,
    offered_question,
    offered_options,
    preparation_method,
    prepared_at
  ) values (
    v_user,
    p_local_id,
    p_source_note,
    p_title,
    p_offered_title,
    p_offered_question,
    p_offered_options,
    p_preparation_method,
    least(p_created_at, now())
  )
  on conflict (owner_id, local_id)
  do update
    set source_note = excluded.source_note,
        proposal_title = excluded.proposal_title,
        offered_title = excluded.offered_title,
        offered_question = excluded.offered_question,
        offered_options = excluded.offered_options,
        preparation_method = excluded.preparation_method,
        prepared_at = excluded.prepared_at,
        updated_at = now()
  returning id into v_proposal;

  return v_proposal;
end;
$$;

create or replace function public.offer_private_proposal(
  p_proposal uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_couple uuid := (select public.my_couple_id());
  v_proposal public.private_proposals;
  v_offered uuid;
begin
  if v_user is null then
    raise exception 'not signed in';
  end if;
  if v_couple is null then
    raise exception 'a WE space is required before offering this';
  end if;

  select * into v_proposal
  from public.private_proposals pp
  where pp.id = p_proposal
    and pp.owner_id = v_user
  for update;
  if v_proposal.id is null then
    raise exception 'private proposal not found';
  end if;

  select ot.id into v_offered
  from public.offered_topics ot
  where ot.private_proposal_id = p_proposal;
  if v_offered is not null then
    return v_offered;
  end if;

  insert into public.offered_topics (
    private_proposal_id,
    owner_id,
    couple_id,
    title,
    question,
    options
  ) values (
    v_proposal.id,
    v_user,
    v_couple,
    v_proposal.offered_title,
    v_proposal.offered_question,
    v_proposal.offered_options
  )
  returning id into v_offered;

  return v_offered;
end;
$$;

revoke all on function private.shared_direction_values(uuid)
  from public, anon, authenticated;
revoke all on function private.remove_private_archive_approaches()
  from public, anon, authenticated;
revoke all on function public.claim_private_proposal(
  uuid,text,text,text,text,text[],text,timestamptz
) from public, anon;
revoke all on function public.offer_private_proposal(uuid)
  from public, anon;
grant execute on function public.claim_private_proposal(
  uuid,text,text,text,text,text[],text,timestamptz
) to authenticated;
grant execute on function public.offer_private_proposal(uuid)
  to authenticated;

-- Raw response rows no longer generate partner-visible realtime events.
do $migration$
begin
  if exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'responses'
  ) then
    execute
      'alter publication supabase_realtime drop table public.responses';
  end if;

  if exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'plan_approaches'
  ) then
    execute
      'alter publication supabase_realtime drop table public.plan_approaches';
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'shared_directions'
  ) then
    execute
      'alter publication supabase_realtime add table public.shared_directions';
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'offered_topics'
  ) then
    execute
      'alter publication supabase_realtime add table public.offered_topics';
  end if;
end;
$migration$;

commit;
