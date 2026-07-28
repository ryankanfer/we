-- WE v2 native: consented intelligence, presence, Anchors, handoffs,
-- Approach, auditable contextual suggestions, Thread, and Seasons.
--
-- Reconciliation-safe by design: this migration may run against either a
-- pristine main schema or a project where the original WE v2 SQL was applied
-- manually through the Supabase SQL editor.

alter table public.responsibilities
  add column if not exists scheduled_on date,
  add column if not exists related_plan_id uuid
    references public.plans(id) on delete set null,
  add column if not exists suggestion_provenance jsonb;

create index if not exists responsibilities_related_plan_active_idx
  on public.responsibilities(couple_id, related_plan_id)
  where status = 'active' and related_plan_id is not null;

create index if not exists responsibilities_related_plan_id_idx
  on public.responsibilities(related_plan_id);

create table if not exists public.relationship_presence (
  couple_id uuid primary key
    references public.couples(id) on delete cascade,
  mode text not null default 'apart'
    check (mode in ('apart', 'together', 'away')),
  changed_by uuid references public.profiles(id) on delete set null,
  changed_at timestamptz not null default now()
);
create index if not exists relationship_presence_changed_by_idx
  on public.relationship_presence(changed_by);

create table if not exists public.signal_consents (
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  profile_id uuid not null
    references public.profiles(id) on delete cascade,
  signal text not null check (signal in (
    'shared_plans',
    'weekly_rhythm',
    'unfinished_threads',
    'private_reflections'
  )),
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (couple_id, profile_id, signal),
  constraint private_reflections_permanently_off
    check (signal <> 'private_reflections' or enabled = false)
);

create index if not exists signal_consents_profile_id_idx
  on public.signal_consents(profile_id);

create or replace function private.seed_signal_consents()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.signal_consents (
    couple_id, profile_id, signal, enabled
  ) values
    (new.couple_id, new.profile_id, 'shared_plans', true),
    (new.couple_id, new.profile_id, 'weekly_rhythm', true),
    (new.couple_id, new.profile_id, 'unfinished_threads', true),
    (new.couple_id, new.profile_id, 'private_reflections', false)
  on conflict (couple_id, profile_id, signal) do nothing;
  return new;
end;
$$;

drop trigger if exists couple_members_seed_signal_consents
  on public.couple_members;
create trigger couple_members_seed_signal_consents
  after insert on public.couple_members
  for each row execute function private.seed_signal_consents();

insert into public.signal_consents (
  couple_id, profile_id, signal, enabled
)
select
  cm.couple_id,
  cm.profile_id,
  signal.value,
  signal.value <> 'private_reflections'
from public.couple_members cm
cross join (
  values
    ('shared_plans'),
    ('weekly_rhythm'),
    ('unfinished_threads'),
    ('private_reflections')
) as signal(value)
on conflict (couple_id, profile_id, signal) do nothing;

create table if not exists public.anchors (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  title text not null
    check (char_length(trim(title)) between 1 and 160),
  note text check (note is null or char_length(note) <= 2000),
  cadence text not null default 'open'
    check (cadence in ('weekly', 'monthly', 'seasonal', 'open')),
  is_active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists anchors_couple_active_idx
  on public.anchors(couple_id, is_active, created_at);
create index if not exists anchors_created_by_idx
  on public.anchors(created_by);

create table if not exists public.responsibility_handoffs (
  id uuid primary key default gen_random_uuid(),
  responsibility_id uuid not null
    references public.responsibilities(id) on delete cascade,
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  from_profile_id uuid not null
    references public.profiles(id) on delete cascade,
  to_profile_id uuid not null
    references public.profiles(id) on delete cascade,
  status text not null default 'offered'
    check (status in ('offered', 'accepted', 'declined', 'withdrawn')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  check (from_profile_id <> to_profile_id)
);

create unique index if not exists responsibility_handoffs_one_open_idx
  on public.responsibility_handoffs(responsibility_id)
  where status = 'offered';
create index if not exists responsibility_handoffs_couple_created_idx
  on public.responsibility_handoffs(couple_id, created_at desc);
create index if not exists responsibility_handoffs_to_profile_idx
  on public.responsibility_handoffs(to_profile_id, status);
create index if not exists responsibility_handoffs_responsibility_idx
  on public.responsibility_handoffs(responsibility_id);
create index if not exists responsibility_handoffs_from_profile_idx
  on public.responsibility_handoffs(from_profile_id);

create table if not exists public.plan_approaches (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.plans(id) on delete cascade,
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  profile_id uuid not null
    references public.profiles(id) on delete cascade,
  approach text not null
    check (approach in ('gently', 'directly', 'together')),
  note text check (note is null or char_length(note) <= 1000),
  revealed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (plan_id, profile_id)
);

create index if not exists plan_approaches_couple_id_idx
  on public.plan_approaches(couple_id);
create index if not exists plan_approaches_profile_id_idx
  on public.plan_approaches(profile_id);

create table if not exists public.relationship_events (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  event_type text not null check (event_type in (
    'plan_completed',
    'responsibility_completed',
    'mutual_resolution',
    'handoff_accepted',
    'shared_moment_opened'
  )),
  source_id uuid not null,
  title text not null
    check (char_length(trim(title)) between 1 and 240),
  occurred_at timestamptz not null default now(),
  provenance jsonb not null default '[]'::jsonb
    check (jsonb_typeof(provenance) = 'array'),
  unique (couple_id, event_type, source_id)
);

create index if not exists relationship_events_couple_occurred_idx
  on public.relationship_events(couple_id, occurred_at);

create table if not exists public.seasons (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  sequence integer not null check (sequence > 0),
  starts_at timestamptz not null,
  cutoff_at timestamptz not null,
  title text not null,
  summary text not null,
  event_ids uuid[] not null check (cardinality(event_ids) >= 6),
  provenance jsonb not null
    check (jsonb_typeof(provenance) = 'array'),
  created_at timestamptz not null default now(),
  unique (couple_id, sequence),
  check (cutoff_at >= starts_at)
);

create index if not exists seasons_couple_cutoff_idx
  on public.seasons(couple_id, cutoff_at desc);

create table if not exists public.contextual_suggestions (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null
    references public.couples(id) on delete cascade,
  kind text not null check (kind in ('party_groceries')),
  related_plan_id uuid not null
    references public.plans(id) on delete cascade,
  title text not null,
  proposed_responsibility_title text not null,
  proposed_scheduled_on date,
  evidence jsonb not null
    check (jsonb_typeof(evidence) = 'object'),
  provenance jsonb not null
    check (jsonb_typeof(provenance) = 'object'),
  created_at timestamptz not null default now(),
  is_eligible boolean not null default true,
  confirmed_responsibility_id uuid
    references public.responsibilities(id) on delete set null,
  unique (couple_id, kind, related_plan_id)
);

create index if not exists contextual_suggestions_couple_open_idx
  on public.contextual_suggestions(couple_id, created_at)
  where confirmed_responsibility_id is null and is_eligible;
create index if not exists contextual_suggestions_related_plan_idx
  on public.contextual_suggestions(related_plan_id);
create index if not exists contextual_suggestions_confirmed_responsibility_idx
  on public.contextual_suggestions(confirmed_responsibility_id);

create table if not exists public.contextual_suggestion_dismissals (
  suggestion_id uuid not null
    references public.contextual_suggestions(id) on delete cascade,
  profile_id uuid not null
    references public.profiles(id) on delete cascade,
  dismissed_at timestamptz not null default now(),
  primary key (suggestion_id, profile_id)
);

create index if not exists contextual_suggestion_dismissals_profile_idx
  on public.contextual_suggestion_dismissals(profile_id);

create table if not exists public.insight_grace (
  insight_id uuid not null
    references public.insights(id) on delete cascade,
  profile_id uuid not null
    references public.profiles(id) on delete cascade,
  decline_count integer not null default 1
    check (decline_count > 0),
  suppress_until timestamptz,
  updated_at timestamptz not null default now(),
  primary key (insight_id, profile_id)
);

create index if not exists insight_grace_profile_id_idx
  on public.insight_grace(profile_id);

-- Preserve declines that predate the grace trigger. The manually applied draft
-- also added decline_count/suppress_until to insight_declines; those harmless
-- legacy columns are intentionally left in place rather than dropped.
insert into public.insight_grace (
  insight_id,
  profile_id,
  decline_count,
  suppress_until,
  updated_at
)
select
  d.insight_id,
  d.profile_id,
  1,
  d.declined_at + interval '3 days',
  d.declined_at
from public.insight_declines d
on conflict (insight_id, profile_id) do nothing;

create or replace function private.record_decline_grace()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.insight_grace (
    insight_id,
    profile_id,
    decline_count,
    suppress_until,
    updated_at
  ) values (
    new.insight_id,
    new.profile_id,
    1,
    now() + interval '3 days',
    now()
  )
  on conflict (insight_id, profile_id) do update
  set decline_count = public.insight_grace.decline_count + 1,
      suppress_until = now() + (
        case
          when public.insight_grace.decline_count >= 2
            then interval '14 days'
          else interval '7 days'
        end
      ),
      updated_at = now();
  return new;
end;
$$;

drop trigger if exists insight_declines_record_grace
  on public.insight_declines;
create trigger insight_declines_record_grace
  after insert or update on public.insight_declines
  for each row execute function private.record_decline_grace();

create or replace function private.mutual_signal_enabled(
  p_couple uuid,
  p_signal text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (
    select count(*)
    from public.signal_consents sc
    where sc.couple_id = p_couple
      and sc.signal = p_signal
      and sc.enabled
  ) = 2;
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
      and case
        when i.seed_key like 'tonight-%'
          or i.seed_key like 'weekend-%'
          then private.mutual_signal_enabled(
            i.couple_id,
            'weekly_rhythm'
          )
        when i.seed_key like 'plan-%'
          or i.seed_key like 'load-%'
          then private.mutual_signal_enabled(
            i.couple_id,
            'shared_plans'
          )
        when i.kind = 'unresolved'
          then private.mutual_signal_enabled(
            i.couple_id,
            'unfinished_threads'
          )
        else true
      end
      and not exists (
        select 1
        from public.insight_grace g
        where g.insight_id = i.id
          and g.profile_id = (select auth.uid())
          and g.suppress_until > now()
      )
  );
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
    r.status in ('submitted', 'revealed')
  from public.responses r
  join public.insights i on i.id = r.insight_id
  where i.couple_id = (select public.my_couple_id())
    and r.profile_id <> (select auth.uid())
    and r.status in ('submitted', 'revealed')
    and public.can_read_insight(i.id);
$$;

alter table public.relationship_presence enable row level security;
alter table public.signal_consents enable row level security;
alter table public.anchors enable row level security;
alter table public.responsibility_handoffs enable row level security;
alter table public.plan_approaches enable row level security;
alter table public.relationship_events enable row level security;
alter table public.seasons enable row level security;
alter table public.contextual_suggestions enable row level security;
alter table public.contextual_suggestion_dismissals enable row level security;
alter table public.insight_grace enable row level security;

drop policy if exists relationship_presence_select
  on public.relationship_presence;
create policy relationship_presence_select
  on public.relationship_presence for select to authenticated
  using (couple_id = (select public.my_couple_id()));

drop policy if exists signal_consents_select_own
  on public.signal_consents;
create policy signal_consents_select_own
  on public.signal_consents for select to authenticated
  using (
    couple_id = (select public.my_couple_id())
    and profile_id = (select auth.uid())
  );

drop policy if exists anchors_select
  on public.anchors;
create policy anchors_select
  on public.anchors for select to authenticated
  using (couple_id = (select public.my_couple_id()));

drop policy if exists responsibility_handoffs_select
  on public.responsibility_handoffs;
create policy responsibility_handoffs_select
  on public.responsibility_handoffs for select to authenticated
  using (couple_id = (select public.my_couple_id()));

drop policy if exists plan_approaches_select
  on public.plan_approaches;
create policy plan_approaches_select
  on public.plan_approaches for select to authenticated
  using (
    couple_id = (select public.my_couple_id())
    and (
      profile_id = (select auth.uid())
      or revealed_at is not null
    )
  );

drop policy if exists relationship_events_select
  on public.relationship_events;
create policy relationship_events_select
  on public.relationship_events for select to authenticated
  using (couple_id = (select public.my_couple_id()));

drop policy if exists seasons_select
  on public.seasons;
create policy seasons_select
  on public.seasons for select to authenticated
  using (couple_id = (select public.my_couple_id()));

drop policy if exists contextual_suggestions_select
  on public.contextual_suggestions;
create policy contextual_suggestions_select
  on public.contextual_suggestions for select to authenticated
  using (couple_id = (select public.my_couple_id()));

drop policy if exists contextual_suggestion_dismissals_select_own
  on public.contextual_suggestion_dismissals;
create policy contextual_suggestion_dismissals_select_own
  on public.contextual_suggestion_dismissals
  for select to authenticated
  using (profile_id = (select auth.uid()));

drop policy if exists insight_grace_select_own
  on public.insight_grace;
create policy insight_grace_select_own
  on public.insight_grace for select to authenticated
  using (profile_id = (select auth.uid()));

grant select on public.relationship_presence to authenticated;
grant select on public.signal_consents to authenticated;
grant select on public.anchors to authenticated;
grant select on public.responsibility_handoffs to authenticated;
grant select on public.plan_approaches to authenticated;
grant select on public.relationship_events to authenticated;
grant select on public.seasons to authenticated;
grant select on public.contextual_suggestions to authenticated;
grant select on public.contextual_suggestion_dismissals to authenticated;
grant select on public.insight_grace to authenticated;

create or replace function private.assert_v2_member(p_couple uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
begin
  if v_user is null
     or p_couple is null
     or p_couple <> (select public.my_couple_id())
     or not exists (
       select 1
       from public.couple_members cm
       where cm.couple_id = p_couple
         and cm.profile_id = v_user
     ) then
    raise exception 'not your active WE space';
  end if;
  return v_user;
end;
$$;

create or replace function public.set_relationship_presence(p_mode text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid := (select public.my_couple_id());
  v_user uuid;
begin
  v_user := private.assert_v2_member(v_couple);
  if p_mode not in ('apart', 'together', 'away') then
    raise exception 'unknown presence mode';
  end if;
  perform private.lock_relationship(v_couple);
  insert into public.relationship_presence (
    couple_id, mode, changed_by, changed_at
  ) values (
    v_couple, p_mode, v_user, now()
  )
  on conflict (couple_id) do update
  set mode = excluded.mode,
      changed_by = excluded.changed_by,
      changed_at = excluded.changed_at;
end;
$$;

create or replace function public.set_signal_consent(
  p_signal text,
  p_enabled boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid := (select public.my_couple_id());
  v_user uuid;
begin
  v_user := private.assert_v2_member(v_couple);
  if p_signal not in (
    'shared_plans',
    'weekly_rhythm',
    'unfinished_threads',
    'private_reflections'
  ) then
    raise exception 'unknown signal';
  end if;
  if p_signal = 'private_reflections' and p_enabled then
    raise exception 'private reflections are permanently excluded';
  end if;
  insert into public.signal_consents (
    couple_id, profile_id, signal, enabled, updated_at
  ) values (
    v_couple,
    v_user,
    p_signal,
    case when p_signal = 'private_reflections' then false else p_enabled end,
    now()
  )
  on conflict (couple_id, profile_id, signal) do update
  set enabled = excluded.enabled,
      updated_at = excluded.updated_at;
end;
$$;

create or replace function public.create_anchor(
  p_couple uuid,
  p_title text,
  p_note text default null,
  p_cadence text default 'open'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
  v_id uuid;
begin
  v_user := private.assert_v2_member(p_couple);
  perform private.lock_relationship(p_couple);
  insert into public.anchors (
    couple_id, title, note, cadence, created_by
  ) values (
    p_couple, trim(p_title), p_note, p_cadence, v_user
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.set_anchor_active(
  p_anchor uuid,
  p_active boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid;
begin
  select a.couple_id into v_couple
  from public.anchors a
  where a.id = p_anchor
    and a.couple_id = (select public.my_couple_id());
  perform private.assert_v2_member(v_couple);
  perform private.lock_relationship(v_couple);
  update public.anchors
  set is_active = p_active,
      updated_at = now()
  where id = p_anchor and couple_id = v_couple;
end;
$$;

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
    plan_id, couple_id, profile_id, approach, note
  ) values (
    p_plan, v_couple, v_user, p_approach, p_note
  )
  on conflict (plan_id, profile_id) do update
  set approach = excluded.approach,
      note = excluded.note,
      revealed_at = null,
      created_at = now();
  if (
    select count(*)
    from public.plan_approaches pa
    where pa.plan_id = p_plan
  ) = 2 then
    update public.plan_approaches
    set revealed_at = coalesce(revealed_at, now())
    where plan_id = p_plan;
  end if;
end;
$$;

create or replace function public.offer_responsibility_handoff(
  p_responsibility uuid,
  p_to_profile uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid;
  v_user uuid := (select auth.uid());
  v_id uuid;
begin
  select r.couple_id into v_couple
  from public.responsibilities r
  where r.id = p_responsibility
    and r.couple_id = (select public.my_couple_id())
    and r.status = 'active';
  perform private.assert_v2_member(v_couple);
  perform private.lock_relationship(v_couple);
  if p_to_profile = v_user
     or not exists (
       select 1 from public.couple_members cm
       where cm.couple_id = v_couple
         and cm.profile_id = p_to_profile
     ) then
    raise exception 'handoff recipient is not your partner';
  end if;
  insert into public.responsibility_handoffs (
    responsibility_id,
    couple_id,
    from_profile_id,
    to_profile_id
  ) values (
    p_responsibility, v_couple, v_user, p_to_profile
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.respond_responsibility_handoff(
  p_handoff uuid,
  p_accept boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_handoff public.responsibility_handoffs%rowtype;
  v_title text;
begin
  select h.* into v_handoff
  from public.responsibility_handoffs h
  where h.id = p_handoff
    and h.to_profile_id = (select auth.uid())
    and h.couple_id = (select public.my_couple_id())
    and h.status = 'offered';
  if v_handoff.id is null then
    raise exception 'handoff is no longer available';
  end if;
  perform private.lock_relationship(v_handoff.couple_id);
  update public.responsibility_handoffs
  set status = case when p_accept then 'accepted' else 'declined' end,
      responded_at = now()
  where id = p_handoff and status = 'offered';
  if p_accept then
    update public.responsibilities
    set owner_id = v_handoff.to_profile_id
    where id = v_handoff.responsibility_id
      and couple_id = v_handoff.couple_id
    returning title into v_title;
    insert into public.relationship_events (
      couple_id, event_type, source_id, title, provenance
    ) values (
      v_handoff.couple_id,
      'handoff_accepted',
      v_handoff.id,
      coalesce(v_title, 'Care changed hands'),
      jsonb_build_array(jsonb_build_object(
        'kind', 'responsibility',
        'id', v_handoff.responsibility_id,
        'label', coalesce(v_title, 'Shared care'),
        'shared', true
      ))
    ) on conflict do nothing;
  end if;
end;
$$;

create or replace function public.withdraw_responsibility_handoff(
  p_handoff uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid;
begin
  select h.couple_id into v_couple
  from public.responsibility_handoffs h
  where h.id = p_handoff
    and h.from_profile_id = (select auth.uid())
    and h.couple_id = (select public.my_couple_id())
    and h.status = 'offered';
  perform private.assert_v2_member(v_couple);
  perform private.lock_relationship(v_couple);
  update public.responsibility_handoffs
  set status = 'withdrawn',
      responded_at = now()
  where id = p_handoff and status = 'offered';
end;
$$;

create or replace function public.refresh_contextual_suggestions(
  p_local_date date
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid := (select public.my_couple_id());
begin
  perform private.assert_v2_member(v_couple);
  update public.contextual_suggestions
  set is_eligible = false
  where couple_id = v_couple
    and kind = 'party_groceries'
    and confirmed_responsibility_id is null;

  if (
    select count(*)
    from public.signal_consents sc
    where sc.couple_id = v_couple
      and sc.signal = 'shared_plans'
      and sc.enabled
  ) < 2 then
    return;
  end if;

  insert into public.contextual_suggestions (
    couple_id,
    kind,
    related_plan_id,
    title,
    proposed_responsibility_title,
    proposed_scheduled_on,
    evidence,
    provenance,
    is_eligible
  )
  select
    p.couple_id,
    'party_groceries',
    p.id,
    'Add a grocery run to the shared list?',
    'Grocery run',
    case
      when p.scheduled_on is null then null
      else p.scheduled_on - 1
    end,
    jsonb_build_object(
      'context', 'For ' || p.title,
      'reason',
        'The party is coming up, and groceries have not been named yet.',
      'sharedInputs', jsonb_build_array(jsonb_build_object(
        'kind', 'plan',
        'id', p.id,
        'label', p.title,
        'shared', true
      ))
    ),
    jsonb_build_object(
      'templateVersion', 1,
      'rule',
        'upcoming shared plan contains a hosting context and no related grocery care exists',
      'generatedAt', now(),
      'references', jsonb_build_array(jsonb_build_object(
        'kind', 'plan',
        'id', p.id,
        'label', p.title,
        'shared', true
      ))
    ),
    true
  from public.plans p
  where p.couple_id = v_couple
    and p.status = 'active'
    and (
      p.scheduled_on is null
      or p.scheduled_on between p_local_date and (p_local_date + 45)
    )
    and lower(p.title || ' ' || coalesce(p.note, ''))
      ~ '(party|gathering|dinner|guest|hosting)'
    and not exists (
      select 1
      from public.responsibilities r
      where r.couple_id = p.couple_id
        and r.related_plan_id = p.id
        and r.status = 'active'
    )
  on conflict (couple_id, kind, related_plan_id) do update
  set proposed_scheduled_on = excluded.proposed_scheduled_on,
      evidence = excluded.evidence,
      provenance = excluded.provenance,
      is_eligible = true
  where public.contextual_suggestions.confirmed_responsibility_id is null;
end;
$$;

create or replace function public.dismiss_contextual_suggestion(
  p_suggestion uuid
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
  select s.couple_id into v_couple
  from public.contextual_suggestions s
  where s.id = p_suggestion
    and s.couple_id = (select public.my_couple_id())
    and s.is_eligible
    and s.confirmed_responsibility_id is null;
  perform private.assert_v2_member(v_couple);
  insert into public.contextual_suggestion_dismissals (
    suggestion_id, profile_id
  ) values (p_suggestion, v_user)
  on conflict (suggestion_id, profile_id) do nothing;
end;
$$;

create or replace function public.confirm_contextual_suggestion(
  p_suggestion uuid,
  p_title text,
  p_note text default null,
  p_owner uuid default null,
  p_scheduled_on date default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_suggestion public.contextual_suggestions%rowtype;
  v_user uuid := (select auth.uid());
  v_responsibility uuid;
begin
  select s.* into v_suggestion
  from public.contextual_suggestions s
  where s.id = p_suggestion
    and s.couple_id = (select public.my_couple_id())
    and s.is_eligible;
  if v_suggestion.id is null then
    raise exception 'suggestion is no longer available';
  end if;
  perform private.assert_v2_member(v_suggestion.couple_id);
  perform private.lock_relationship(v_suggestion.couple_id);
  select s.* into v_suggestion
  from public.contextual_suggestions s
  where s.id = p_suggestion
  for update;
  if v_suggestion.confirmed_responsibility_id is not null then
    return v_suggestion.confirmed_responsibility_id;
  end if;
  if p_owner is not null
     and not exists (
       select 1 from public.couple_members cm
       where cm.couple_id = v_suggestion.couple_id
         and cm.profile_id = p_owner
     ) then
    raise exception 'responsibility owner is not in this WE space';
  end if;
  select r.id into v_responsibility
  from public.responsibilities r
  where r.couple_id = v_suggestion.couple_id
    and r.related_plan_id = v_suggestion.related_plan_id
    and r.status = 'active'
  limit 1;
  if v_responsibility is null then
    insert into public.responsibilities (
      couple_id,
      title,
      note,
      owner_id,
      scheduled_on,
      related_plan_id,
      suggestion_provenance
    ) values (
      v_suggestion.couple_id,
      trim(p_title),
      p_note,
      p_owner,
      p_scheduled_on,
      v_suggestion.related_plan_id,
      v_suggestion.provenance
    ) returning id into v_responsibility;
  end if;
  update public.contextual_suggestions
  set confirmed_responsibility_id = v_responsibility
  where id = p_suggestion;
  return v_responsibility;
end;
$$;

create or replace function private.record_shared_closure()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_type text;
  v_kind text;
begin
  if old.status = 'completed' or new.status <> 'completed' then
    return new;
  end if;
  if tg_table_name = 'plans' then
    v_event_type := 'plan_completed';
    v_kind := 'plan';
  else
    v_event_type := 'responsibility_completed';
    v_kind := 'responsibility';
  end if;
  insert into public.relationship_events (
    couple_id, event_type, source_id, title, occurred_at, provenance
  ) values (
    new.couple_id,
    v_event_type,
    new.id,
    new.title,
    coalesce(new.completed_at, now()),
    jsonb_build_array(jsonb_build_object(
      'kind', v_kind,
      'id', new.id,
      'label', new.title,
      'shared', true
    ))
  ) on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists plans_record_shared_closure
  on public.plans;
create trigger plans_record_shared_closure
  after update of status on public.plans
  for each row execute function private.record_shared_closure();

drop trigger if exists responsibilities_record_shared_closure
  on public.responsibilities;
create trigger responsibilities_record_shared_closure
  after update of status on public.responsibilities
  for each row execute function private.record_shared_closure();

create or replace function private.record_mutual_resolution()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_insight public.insights%rowtype;
begin
  if old.resolution_type is not null
     or new.resolution_type is null then
    return new;
  end if;
  select i.* into v_insight
  from public.insights i
  where i.id = new.insight_id;
  insert into public.relationship_events (
    couple_id, event_type, source_id, title, occurred_at, provenance
  ) values (
    v_insight.couple_id,
    'mutual_resolution',
    v_insight.id,
    v_insight.title,
    coalesce(new.resolved_at, now()),
    jsonb_build_array(jsonb_build_object(
      'kind', 'relationship_event',
      'id', v_insight.id,
      'label', v_insight.title,
      'shared', true
    ))
  ) on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists insight_consent_record_mutual_resolution
  on public.insight_consent;
create trigger insight_consent_record_mutual_resolution
  after update of resolution_type on public.insight_consent
  for each row execute function private.record_mutual_resolution();

create or replace function public.create_ready_season()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid := (select public.my_couple_id());
  v_previous_cutoff timestamptz;
  v_start timestamptz;
  v_count integer;
  v_types integer;
  v_months integer;
  v_ids uuid[];
  v_provenance jsonb;
  v_sequence integer;
  v_id uuid;
begin
  perform private.assert_v2_member(v_couple);
  perform private.lock_relationship(v_couple);
  select max(s.cutoff_at), coalesce(max(s.sequence), 0) + 1
  into v_previous_cutoff, v_sequence
  from public.seasons s
  where s.couple_id = v_couple;
  select
    min(e.occurred_at),
    count(*),
    count(distinct e.event_type),
    count(distinct date_trunc('month', e.occurred_at)),
    array_agg(e.id order by e.occurred_at),
    jsonb_agg(jsonb_build_object(
      'kind', 'relationship_event',
      'id', e.id,
      'label', e.title,
      'shared', true
    ) order by e.occurred_at)
  into
    v_start, v_count, v_types, v_months, v_ids, v_provenance
  from public.relationship_events e
  where e.couple_id = v_couple
    and (v_previous_cutoff is null or e.occurred_at > v_previous_cutoff)
    and e.occurred_at <= now();
  if v_start is null
     or now() < v_start + interval '6 weeks'
     or v_count < 6
     or v_types < 2
     or v_months < 2 then
    raise exception 'a season is not ready';
  end if;
  insert into public.seasons (
    couple_id,
    sequence,
    starts_at,
    cutoff_at,
    title,
    summary,
    event_ids,
    provenance
  ) values (
    v_couple,
    v_sequence,
    v_start,
    now(),
    'A season of showing up',
    format('%s shared moments formed this season.', v_count),
    v_ids,
    v_provenance
  ) returning id into v_id;
  return v_id;
end;
$$;

-- Upgrade deletion archives without exposing owner-private dismissals,
-- signal choices, reflections, or unrevealed approaches.
alter table public.relationship_archives
  drop constraint if exists relationship_archives_snapshot_version_check;
alter table public.relationship_archives
  add constraint relationship_archives_snapshot_version_check
  check (snapshot_version in (1, 2));

create or replace function private.enrich_v2_relationship_archive()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid;
begin
  select cm.couple_id into v_couple
  from public.couple_members cm
  where cm.profile_id = new.owner_id
  limit 1;
  if v_couple is null then
    return new;
  end if;
  new.snapshot_version := 2;
  new.snapshot := new.snapshot || jsonb_build_object(
    'responsibilities', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'title', r.title,
        'note', r.note,
        'ownership', case
          when r.owner_id is null then 'together'
          when r.owner_id = new.owner_id then 'me'
          else 'partner'
        end,
        'scheduledOn', r.scheduled_on,
        'relatedPlanID', r.related_plan_id,
        'suggestionProvenance', r.suggestion_provenance,
        'status', r.status,
        'completedAt', r.completed_at,
        'updatedAt', r.updated_at
      ) order by r.created_at)
      from public.responsibilities r
      where r.couple_id = v_couple
    ), '[]'::jsonb),
    'anchors', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id,
        'coupleID', a.couple_id,
        'title', a.title,
        'note', a.note,
        'cadence', a.cadence,
        'isActive', a.is_active,
        'createdBy', a.created_by,
        'createdAt', a.created_at,
        'updatedAt', a.updated_at
      ) order by a.created_at)
      from public.anchors a
      where a.couple_id = v_couple
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id,
        'coupleID', e.couple_id,
        'type', e.event_type,
        'sourceID', e.source_id,
        'title', e.title,
        'occurredAt', e.occurred_at,
        'provenance', e.provenance
      ) order by e.occurred_at)
      from public.relationship_events e
      where e.couple_id = v_couple
    ), '[]'::jsonb),
    'seasons', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id,
        'coupleID', s.couple_id,
        'sequence', s.sequence,
        'startsAt', s.starts_at,
        'cutoffAt', s.cutoff_at,
        'title', s.title,
        'summary', s.summary,
        'eventIDs', s.event_ids,
        'provenance', s.provenance,
        'createdAt', s.created_at
      ) order by s.sequence)
      from public.seasons s
      where s.couple_id = v_couple
    ), '[]'::jsonb),
    'handoffs', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', h.id,
        'responsibilityID', h.responsibility_id,
        'coupleID', h.couple_id,
        'fromProfileID', h.from_profile_id,
        'toProfileID', h.to_profile_id,
        'status', h.status,
        'createdAt', h.created_at,
        'respondedAt', h.responded_at
      ) order by h.created_at)
      from public.responsibility_handoffs h
      where h.couple_id = v_couple
    ), '[]'::jsonb),
    'approaches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id,
        'planID', a.plan_id,
        'profileID', a.profile_id,
        'approach', a.approach,
        'note', a.note,
        'revealedAt', a.revealed_at,
        'createdAt', a.created_at
      ) order by a.created_at)
      from public.plan_approaches a
      where a.couple_id = v_couple
        and a.revealed_at is not null
    ), '[]'::jsonb)
  );
  return new;
end;
$$;

drop trigger if exists relationship_archives_enrich_v2
  on public.relationship_archives;
create trigger relationship_archives_enrich_v2
  before insert on public.relationship_archives
  for each row execute function private.enrich_v2_relationship_archive();

revoke all on function private.assert_v2_member(uuid)
  from public, anon, authenticated;
revoke all on function private.seed_signal_consents()
  from public, anon, authenticated;
revoke all on function private.record_decline_grace()
  from public, anon, authenticated;
revoke all on function private.mutual_signal_enabled(uuid,text)
  from public, anon, authenticated;
revoke all on function private.record_shared_closure()
  from public, anon, authenticated;
revoke all on function private.record_mutual_resolution()
  from public, anon, authenticated;
revoke all on function private.enrich_v2_relationship_archive()
  from public, anon, authenticated;

revoke all on function public.set_relationship_presence(text)
  from public, anon;
revoke all on function public.partner_answer_statuses()
  from public, anon;
revoke all on function public.set_signal_consent(text,boolean)
  from public, anon;
revoke all on function public.create_anchor(uuid,text,text,text)
  from public, anon;
revoke all on function public.set_anchor_active(uuid,boolean)
  from public, anon;
revoke all on function public.set_plan_approach(uuid,text,text)
  from public, anon;
revoke all on function public.offer_responsibility_handoff(uuid,uuid)
  from public, anon;
revoke all on function public.respond_responsibility_handoff(uuid,boolean)
  from public, anon;
revoke all on function public.withdraw_responsibility_handoff(uuid)
  from public, anon;
revoke all on function public.refresh_contextual_suggestions(date)
  from public, anon;
revoke all on function public.dismiss_contextual_suggestion(uuid)
  from public, anon;
revoke all on function public.confirm_contextual_suggestion(
  uuid,text,text,uuid,date
) from public, anon;
revoke all on function public.create_ready_season()
  from public, anon;

grant execute on function public.set_relationship_presence(text)
  to authenticated;
grant execute on function public.partner_answer_statuses()
  to authenticated;
grant execute on function public.set_signal_consent(text,boolean)
  to authenticated;
grant execute on function public.create_anchor(uuid,text,text,text)
  to authenticated;
grant execute on function public.set_anchor_active(uuid,boolean)
  to authenticated;
grant execute on function public.set_plan_approach(uuid,text,text)
  to authenticated;
grant execute on function public.offer_responsibility_handoff(uuid,uuid)
  to authenticated;
grant execute on function public.respond_responsibility_handoff(uuid,boolean)
  to authenticated;
grant execute on function public.withdraw_responsibility_handoff(uuid)
  to authenticated;
grant execute on function public.refresh_contextual_suggestions(date)
  to authenticated;
grant execute on function public.dismiss_contextual_suggestion(uuid)
  to authenticated;
grant execute on function public.confirm_contextual_suggestion(
  uuid,text,text,uuid,date
) to authenticated;
grant execute on function public.create_ready_season()
  to authenticated;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'relationship_presence',
    'signal_consents',
    'anchors',
    'responsibility_handoffs',
    'plan_approaches',
    'relationship_events',
    'seasons',
    'contextual_suggestions',
    'contextual_suggestion_dismissals',
    'insight_grace'
  ]
  loop
    if not exists (
      select 1
      from pg_catalog.pg_publication_tables pt
      where pt.pubname = 'supabase_realtime'
        and pt.schemaname = 'public'
        and pt.tablename = v_table
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        v_table
      );
    end if;
  end loop;
end;
$$;
