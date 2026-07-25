-- WE — schema, row-level security, and the consent state machine.
-- Applied to project "we-round1" (org "we"). This file is the reproducible source.
-- The live project recorded the original setup across migration versions
-- 20260724015432, 20260724015550, and 20260724015812. This first file contains
-- the consolidated reproducible end state; the two companion markers preserve
-- that existing remote history for safe future dry-runs.
--
-- The consent invariants live in the database, not just the UI:
--   * a partner's private reflection is unreadable by the other person
--   * a partner's answer is unreadable until BOTH have submitted (revealed together)
-- All state transitions run through SECURITY DEFINER functions; clients get
-- read-only RLS and cannot mutate consent state directly.

create extension if not exists pgcrypto;

-- ---- Tables --------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

create table public.couples (
  id uuid primary key default gen_random_uuid(),
  join_code text not null unique,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.couple_members (
  couple_id uuid not null references public.couples(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  hue text not null check (hue in ('burgundy','sage')),
  joined_at timestamptz not null default now(),
  primary key (couple_id, profile_id)
);

create table public.insights (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  seed_key text not null,
  kind text not null check (kind in ('logistical','relational','unresolved')),
  domain text not null check (domain in ('life','us')),
  present boolean not null default false,
  title text not null,
  body text not null,
  evidence text not null,
  source text not null,
  options text[] not null,
  sort int not null default 0,
  created_at timestamptz not null default now()
);

create table public.insight_consent (
  insight_id uuid primary key references public.insights(id) on delete cascade,
  visibility text not null default 'shared' check (visibility in ('private','shared','mutual')),
  owner_id uuid references public.profiles(id),
  readiness text not null default 'idle'
    check (readiness in ('idle','requested','accepted','declined','withdrawn')),
  initiator_id uuid references public.profiles(id),
  requested_at timestamptz,
  accepted_at timestamptz,
  resolution_type text check (resolution_type in ('settled','released','leftOpen')),
  resolution_choice text,
  resolved_at timestamptz
);

create table public.responses (
  insight_id uuid not null references public.insights(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'none' check (status in ('none','draft','submitted','revealed')),
  choice text,
  note text,
  updated_at timestamptz not null default now(),
  primary key (insight_id, profile_id)
);

create table public.dismissals (
  insight_id uuid not null references public.insights(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  primary key (insight_id, profile_id)
);

create table public.reflections (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  domain text not null check (domain in ('life','us')),
  kind text not null check (kind in ('reflection','suggestion')),
  text text not null,
  created_at timestamptz not null default now()
);

-- ---- Helpers -------------------------------------------------------------

-- One couple per person; SECURITY DEFINER avoids recursive RLS on membership.
create or replace function public.my_couple_id()
returns uuid language sql stable security definer set search_path = public as $$
  select couple_id from public.couple_members where profile_id = auth.uid() limit 1;
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data->>'name', ''), 'Someone'));
  return new;
end; $$;

create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();

-- ---- Row-level security --------------------------------------------------

alter table public.profiles enable row level security;
alter table public.couples enable row level security;
alter table public.couple_members enable row level security;
alter table public.insights enable row level security;
alter table public.insight_consent enable row level security;
alter table public.responses enable row level security;
alter table public.dismissals enable row level security;
alter table public.reflections enable row level security;

create policy profiles_select on public.profiles for select
  using (id = auth.uid()
         or id in (select profile_id from public.couple_members where couple_id = public.my_couple_id()));
create policy profiles_update on public.profiles for update using (id = auth.uid());

create policy couples_select on public.couples for select using (id = public.my_couple_id());
create policy couple_members_select on public.couple_members for select using (couple_id = public.my_couple_id());
create policy insights_select on public.insights for select using (couple_id = public.my_couple_id());
create policy insight_consent_select on public.insight_consent for select
  using (insight_id in (select id from public.insights where couple_id = public.my_couple_id()));

-- THE privacy invariant: your own answer always; the partner's ONLY once revealed.
create policy responses_select on public.responses for select
  using (
    insight_id in (select id from public.insights where couple_id = public.my_couple_id())
    and (profile_id = auth.uid() or status = 'revealed')
  );

create policy dismissals_select on public.dismissals for select using (profile_id = auth.uid());
create policy reflections_select on public.reflections for select using (owner_id = auth.uid());
create policy reflections_insert on public.reflections for insert
  with check (owner_id = auth.uid() and couple_id = public.my_couple_id());

-- Realtime for the shared surfaces (RLS still filters each client's payload).
alter publication supabase_realtime add table public.insight_consent;
alter publication supabase_realtime add table public.responses;
alter publication supabase_realtime add table public.dismissals;
alter publication supabase_realtime add table public.reflections;
alter publication supabase_realtime add table public.couple_members;

-- ---- Consent state machine (mirrors lib/consent.ts) ----------------------

create or replace function public.gen_join_code()
returns text language plpgsql security definer set search_path = public as $$
declare v_code text;
begin
  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from public.couples where join_code = v_code);
  end loop;
  return v_code;
end $$;

create or replace function public.partner_id(p_couple uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select profile_id from public.couple_members
   where couple_id = p_couple and profile_id <> auth.uid() limit 1;
$$;

create or replace function public.seed_couple_insights(p_couple uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.insights (couple_id, seed_key, kind, domain, present, title, body, evidence, source, options, sort) values
  (p_couple, 'saturday-errands', 'logistical', 'life', true,
    'Three errands are competing for Saturday.',
    'The pharmacy pickup, the hardware return, and the grocery run are all pointing at the same morning. Folded together, they are one loop that ends by noon.',
    'Three open tasks reference Saturday, and the last two Saturdays both filled up by 10 AM.',
    'Task list · recent Saturdays',
    array['Fold them into one plan','Split them between us','Leave Saturday open'], 1),
  (p_couple, 'evening-together', 'relational', 'us', true,
    'You haven''t had an evening that belonged only to you two in eleven days.',
    'Nothing is wrong. The calendar has simply been full of everything else. Tomorrow is open after 7:30.',
    'Eleven days since the last shared evening with nothing scheduled around it.',
    'Shared calendar · time-together pattern',
    array['Take tomorrow, after 7:30','Pick another night this week','Let this week pass'], 2),
  (p_couple, 'august-trip', 'unresolved', 'life', false,
    'The August trip question keeps returning.',
    'It has been set aside twice, each time with the same words: "let''s decide later." Later keeps arriving. It might be lighter to hold it once, together, than to keep carrying it separately.',
    'Postponed twice over three weeks, most recently nine days ago.',
    'Decisions · postponement pattern',
    array['Keep it','Change it','Let this go together'], 3),
  (p_couple, 'unhurried-time', 'relational', 'us', false,
    'It''s been a while since you were together with nowhere to be.',
    'Not a plan, not an occasion — just unhurried time. Those hours have quietly thinned out over the last few weeks.',
    'No unscheduled time together, longer than an hour, in the last two weeks.',
    'Shared calendar · rhythm of unplanned time',
    array['Make a little room this week','Leave space for it to happen','Let this pass'], 4);

  insert into public.insight_consent (insight_id)
    select id from public.insights where couple_id = p_couple;
end $$;

create or replace function public.create_couple()
returns json language plpgsql security definer set search_path = public as $$
declare v_couple uuid; v_code text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if public.my_couple_id() is not null then raise exception 'already in a couple'; end if;
  v_code := public.gen_join_code();
  insert into public.couples (join_code, created_by) values (v_code, auth.uid()) returning id into v_couple;
  insert into public.couple_members (couple_id, profile_id, hue) values (v_couple, auth.uid(), 'burgundy');
  perform public.seed_couple_insights(v_couple);
  return json_build_object('couple_id', v_couple, 'join_code', v_code);
end $$;

create or replace function public.join_couple(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare v_couple uuid; v_count int;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if public.my_couple_id() is not null then raise exception 'already in a couple'; end if;
  select id into v_couple from public.couples where join_code = upper(trim(p_code));
  if v_couple is null then raise exception 'that code doesn''t match anything'; end if;
  select count(*) into v_count from public.couple_members where couple_id = v_couple;
  if v_count >= 2 then raise exception 'this space already has two people'; end if;
  insert into public.couple_members (couple_id, profile_id, hue) values (v_couple, auth.uid(), 'sage');
  return json_build_object('couple_id', v_couple);
end $$;

create or replace function public.assert_my_insight(p_insight uuid)
returns uuid language plpgsql stable security definer set search_path = public as $$
declare v_couple uuid;
begin
  select couple_id into v_couple from public.insights where id = p_insight;
  if v_couple is null or v_couple <> public.my_couple_id() then raise exception 'not your insight'; end if;
  return v_couple;
end $$;

create or replace function public.request_reveal(p_insight uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c public.insight_consent;
begin
  perform public.assert_my_insight(p_insight);
  select * into c from public.insight_consent where insight_id = p_insight for update;
  if c.resolution_type is not null then raise exception 'already resolved'; end if;
  if c.readiness not in ('idle','withdrawn') then raise exception 'reveal already in motion'; end if;
  if c.visibility = 'private' and c.owner_id <> auth.uid() then raise exception 'not your private item'; end if;
  update public.insight_consent set
    visibility = case when visibility = 'mutual' then 'mutual' else 'shared' end,
    owner_id = null, readiness = 'requested', initiator_id = auth.uid(),
    requested_at = now(), accepted_at = null
  where insight_id = p_insight;
end $$;

create or replace function public.accept_reveal(p_insight uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c public.insight_consent;
begin
  perform public.assert_my_insight(p_insight);
  select * into c from public.insight_consent where insight_id = p_insight for update;
  if c.readiness not in ('requested','declined') then raise exception 'nothing to accept'; end if;
  if c.initiator_id = auth.uid() then raise exception 'cannot accept your own request'; end if;
  update public.insight_consent set readiness = 'accepted', visibility = 'mutual', accepted_at = now()
  where insight_id = p_insight;
end $$;

create or replace function public.decline_reveal(p_insight uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c public.insight_consent;
begin
  perform public.assert_my_insight(p_insight);
  select * into c from public.insight_consent where insight_id = p_insight for update;
  if c.readiness <> 'requested' then raise exception 'nothing to decline'; end if;
  if c.initiator_id = auth.uid() then raise exception 'cannot decline your own request'; end if;
  update public.insight_consent set readiness = 'declined' where insight_id = p_insight;
end $$;

create or replace function public.withdraw_reveal(p_insight uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c public.insight_consent;
begin
  perform public.assert_my_insight(p_insight);
  select * into c from public.insight_consent where insight_id = p_insight for update;
  if c.readiness not in ('requested','declined') then raise exception 'nothing to withdraw'; end if;
  if c.initiator_id <> auth.uid() then raise exception 'only the initiator can withdraw'; end if;
  update public.insight_consent set readiness = 'withdrawn', initiator_id = null, requested_at = null
  where insight_id = p_insight;
end $$;

-- When both have submitted, both flip to revealed in the same statement.
create or replace function public.submit_response(p_insight uuid, p_choice text, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare c public.insight_consent; v_couple uuid; v_partner uuid; v_my text; v_ptr text;
begin
  v_couple := public.assert_my_insight(p_insight);
  select * into c from public.insight_consent where insight_id = p_insight for update;
  if c.visibility <> 'mutual' then raise exception 'answers happen only once opened together'; end if;
  select status into v_my from public.responses where insight_id = p_insight and profile_id = auth.uid();
  if v_my in ('submitted','revealed') then raise exception 'already submitted'; end if;

  insert into public.responses (insight_id, profile_id, status, choice, note, updated_at)
  values (p_insight, auth.uid(), 'submitted', p_choice, p_note, now())
  on conflict (insight_id, profile_id)
  do update set status = 'submitted', choice = excluded.choice, note = excluded.note, updated_at = now();

  v_partner := public.partner_id(v_couple);
  select status into v_ptr from public.responses where insight_id = p_insight and profile_id = v_partner;
  if v_ptr = 'submitted' then
    update public.responses set status = 'revealed', updated_at = now()
    where insight_id = p_insight and profile_id in (auth.uid(), v_partner);
  end if;
end $$;

create or replace function public.resolve_insight(p_insight uuid, p_type text, p_choice text)
returns void language plpgsql security definer set search_path = public as $$
declare v_revealed int;
begin
  perform public.assert_my_insight(p_insight);
  if p_type not in ('settled','released','leftOpen') then raise exception 'bad resolution'; end if;
  select count(*) into v_revealed from public.responses where insight_id = p_insight and status = 'revealed';
  if v_revealed < 2 then raise exception 'cannot resolve before both answers are revealed'; end if;
  update public.insight_consent
     set resolution_type = p_type, resolution_choice = p_choice, resolved_at = now()
   where insight_id = p_insight;
end $$;

create or replace function public.dismiss_suggestion(p_insight uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c public.insight_consent;
begin
  perform public.assert_my_insight(p_insight);
  select * into c from public.insight_consent where insight_id = p_insight for update;
  if c.readiness not in ('idle','withdrawn') then raise exception 'cannot dismiss once it is between you'; end if;
  insert into public.dismissals (insight_id, profile_id) values (p_insight, auth.uid()) on conflict do nothing;
end $$;

-- ---- Grants --------------------------------------------------------------
-- my_couple_id stays executable by authenticated: RLS policies evaluate it as
-- the querying role. Internal helpers are locked to the definer functions only.

grant execute on function
  public.create_couple(), public.join_couple(text),
  public.request_reveal(uuid), public.accept_reveal(uuid), public.decline_reveal(uuid),
  public.withdraw_reveal(uuid), public.submit_response(uuid, text, text),
  public.resolve_insight(uuid, text, text), public.dismiss_suggestion(uuid)
to authenticated;

revoke execute on function public.handle_new_user() from anon, authenticated, public;
revoke execute on function public.seed_couple_insights(uuid) from anon, authenticated, public;
revoke execute on function public.gen_join_code() from anon, authenticated, public;
revoke execute on function public.partner_id(uuid) from anon, authenticated, public;
revoke execute on function public.assert_my_insight(uuid) from anon, authenticated, public;
revoke execute on function
  public.create_couple(), public.join_couple(text),
  public.request_reveal(uuid), public.accept_reveal(uuid), public.decline_reveal(uuid),
  public.withdraw_reveal(uuid), public.submit_response(uuid, text, text),
  public.resolve_insight(uuid, text, text), public.dismiss_suggestion(uuid)
from anon, public;
