-- An invitation is an offer with an end. Phase 2d, and a P0.
--
-- WHAT IS WRONG TODAY
--
-- `couples.join_code` is generated once, in `create_couple()`, and then never
-- changes, never expires, and cannot be withdrawn. `join_couple()` at
-- `20260725035142:370` checks three things: that you are signed in, that you
-- are not already coupled, and that the space has fewer than two people. The
-- code itself is never questioned.
--
-- So a code is a permanent key to a relationship. Pasted into a group thread
-- once, screenshotted, left in a message history, or simply typed where
-- somebody could see it, and it stays live forever. The only thing standing
-- between a stranger and somebody's shared field is that the second slot
-- happens to be full — and after `20260808000000`, a slot can be vacated by a
-- partner deleting their account. A code shared in month one becomes live
-- again in month nine, silently, at the worst possible moment.
--
-- CIRCLE.md:43 already names the state this is missing:
--
--   | Two circles, apart | invited, not yet joined |
--
-- There is a picture for it and no data behind it. `PendingInvitation.swift`
-- holds a typed or tapped code on the client until there is a session to
-- spend it on, but nothing server-side has ever modelled an invitation as a
-- thing with a beginning and an end.
--
-- WHAT AN INVITATION IS HERE
--
--   bounded    seven days by default, then it is not a code any more
--   single use consumed the moment it is redeemed
--   revocable  withdrawn by the person who sent it, without waiting
--   singular   one live invitation per couple, so "the code" is unambiguous
--
-- Regenerating revokes the previous one in the same statement. That is the
-- honest reading of "I sent the wrong person my code" — the old one must stop
-- working at the instant the new one starts, not merely become less
-- convenient.
--
-- WHY `couples.join_code` STAYS
--
-- `Models.swift:20` declares `Couple.joinCode` as a non-optional `String` and
-- `DTOs.swift:383` decodes it from this column. Dropping or nulling it breaks
-- decoding for every client in the field, including ones already installed.
--
-- So the column survives as a **mirror**: it always holds the code of the
-- couple's current live invitation, maintained by the same three RPCs that
-- maintain the invitation itself. Every existing read path keeps working and
-- keeps showing the right string. What it stops being is a credential —
-- `join_couple` no longer consults it, and a code that has expired, been
-- consumed, or been revoked is refused even though the mirror may still show
-- it until the next regeneration.
--
-- `join_code_expires_at` joins it, for the same reason and on the same terms.
-- The alternative was an embedded PostgREST select against `invitations`,
-- which needs the embedded rows filtered down to the live one and turns a
-- one-column read into a shape the client has to reason about. Both mirrors
-- are maintained at exactly three points — `create_couple`,
-- `create_invitation`, `revoke_invitation` — and nowhere else.
--
-- Once no supported client decodes `join_code`, both columns can be dropped in
-- one line. That is deliberately a separate migration from this one.
--
-- IN-FLIGHT CODES
--
-- Every unpaired couple gets its existing code seeded as a live invitation
-- with a full window starting now, so anybody mid-pairing when this deploys
-- has seven days rather than an error they cannot explain. Couples that are
-- already two people get nothing: they have no use for an invitation, and
-- minting one would be handing out a key nobody asked for.

begin;

-- MARK: The mirror ----------------------------------------------------------

alter table public.couples
  add column if not exists join_code_expires_at timestamptz;

-- MARK: The invitation ------------------------------------------------------

create table if not exists public.invitations (
  id uuid primary key default gen_random_uuid(),

  couple_id uuid not null
    references public.couples(id) on delete cascade,

  -- Same shape and generator as the code it replaces: sixteen uppercase hex
  -- characters, which is exactly what `PendingInvitation.normalized` accepts
  -- and truncates to. A code the client would silently reshape is a code that
  -- fails to match for reasons nobody can see.
  code text not null unique
    check (code = upper(code) and char_length(code) between 6 and 16),

  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),

  expires_at timestamptz not null,

  consumed_at timestamptz,
  consumed_by uuid references public.profiles(id) on delete set null,

  revoked_at timestamptz,

  -- Consumption is one event, not two half-recorded ones.
  constraint invitations_consumed_together check (
    (consumed_at is null and consumed_by is null)
    or (consumed_at is not null and consumed_by is not null)
  ),

  -- An invitation is spent or withdrawn, never both. Without this, a race
  -- between redeeming and revoking could record an outcome that never
  -- happened.
  constraint invitations_one_ending check (
    consumed_at is null or revoked_at is null
  ),

  constraint invitations_window_forward check (expires_at > created_at)
);

-- One live invitation per couple. This is the constraint that makes "the
-- code" a well-formed phrase, and it is enforced here rather than in the RPC
-- so that two concurrent regenerations cannot both win.
create unique index if not exists invitations_one_live_per_couple
  on public.invitations(couple_id)
  where consumed_at is null and revoked_at is null;

create index if not exists invitations_code_live_idx
  on public.invitations(code)
  where consumed_at is null and revoked_at is null;

alter table public.invitations enable row level security;

-- Read your own couple's invitations. Redemption deliberately needs no read
-- grant: the person redeeming is by definition not a member yet, and
-- `join_couple` is security definer. A policy that let them read invitations
-- would let anyone enumerate live codes.
drop policy if exists invitations_select on public.invitations;
create policy invitations_select on public.invitations
  for select using (couple_id = public.my_couple_id());

-- Every write goes through an RPC. Direct writes would let a client set its
-- own `expires_at`, which is the whole point of the window.
revoke insert, update, delete on public.invitations
  from anon, authenticated;
grant select on public.invitations to authenticated;

-- MARK: The window ----------------------------------------------------------

create or replace function private.invitation_window()
returns interval
language sql
immutable
set search_path = ''
as $$ select interval '7 days' $$;

revoke all on function private.invitation_window()
  from public, anon, authenticated;

-- MARK: Issuing -------------------------------------------------------------
--
-- Revoke-then-issue in one statement pair, inside the caller's transaction,
-- under a row lock on the couple. The unique index above is the backstop if
-- two devices ask at the same moment.

create or replace function public.create_invitation()
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_couple uuid := (select public.my_couple_id());
  v_members integer;
  v_code text;
  v_expires timestamptz;
begin
  if v_user is null or v_couple is null then
    raise exception 'not signed into a relationship';
  end if;

  perform 1 from public.couples where id = v_couple for update;

  select count(*) into v_members
  from public.couple_members cm
  where cm.couple_id = v_couple;

  if v_members >= 2 then
    raise exception 'this space already has two people';
  end if;

  update public.invitations
  set revoked_at = now()
  where couple_id = v_couple
    and consumed_at is null
    and revoked_at is null;

  v_code := public.gen_join_code();
  v_expires := now() + private.invitation_window();

  insert into public.invitations (
    couple_id, code, created_by, expires_at
  ) values (
    v_couple, v_code, v_user, v_expires
  );

  -- The mirror. See the header: this keeps `Couple.joinCode` truthful for
  -- clients that still decode it, without making it the thing that authorises
  -- anything.
  update public.couples
  set join_code = v_code,
      join_code_expires_at = v_expires
  where id = v_couple;

  return json_build_object(
    'code', v_code,
    'expires_at', v_expires
  );
end;
$$;

revoke all on function public.create_invitation() from public, anon;
grant execute on function public.create_invitation() to authenticated;

-- MARK: Withdrawing ---------------------------------------------------------

create or replace function public.revoke_invitation()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid := (select public.my_couple_id());
begin
  if (select auth.uid()) is null or v_couple is null then
    raise exception 'not signed into a relationship';
  end if;

  perform 1 from public.couples where id = v_couple for update;

  update public.invitations
  set revoked_at = now()
  where couple_id = v_couple
    and consumed_at is null
    and revoked_at is null;

  -- Nothing is live, so the mirror must not show a code that would be
  -- refused. `join_code` is `not null unique`, so it holds a value that
  -- cannot be redeemed rather than nothing at all; the null expiry is what
  -- tells the client there is no invitation to display.
  update public.couples
  set join_code = public.gen_join_code(),
      join_code_expires_at = null
  where id = v_couple;
end;
$$;

revoke all on function public.revoke_invitation() from public, anon;
grant execute on function public.revoke_invitation() to authenticated;

-- MARK: Redeeming -----------------------------------------------------------
--
-- Replaces the body from `20260808000000`, which still resolved through
-- `couples.join_code`. The slot selection there is unchanged and still
-- load-bearing — see that migration's header on vacated slots.
--
-- The four refusals are deliberately distinct strings. "That invitation has
-- expired" and "that code does not match anything" are different facts about
-- the world, and collapsing them into one message to seem cautious would only
-- mean somebody retypes a code that was never going to work.

create or replace function public.join_couple(p_code text)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_invitation public.invitations;
  v_couple uuid;
  v_count integer;
  v_slot smallint;
begin
  if v_user is null then
    raise exception 'not signed in';
  end if;
  if (select public.my_couple_id()) is not null then
    raise exception 'already in a couple';
  end if;

  -- The row lock makes concurrent redemptions of the same code take turns.
  select * into v_invitation
  from public.invitations i
  where i.code = upper(trim(p_code))
  for update;

  if v_invitation.id is null then
    raise exception 'that code does not match anything';
  end if;
  if v_invitation.revoked_at is not null then
    raise exception 'that invitation was withdrawn';
  end if;
  if v_invitation.consumed_at is not null then
    raise exception 'that invitation has already been used';
  end if;
  if v_invitation.expires_at <= now() then
    raise exception 'that invitation has expired';
  end if;

  v_couple := v_invitation.couple_id;

  perform 1 from public.couples where id = v_couple for update;

  select count(*) into v_count
  from public.couple_members cm
  where cm.couple_id = v_couple;

  if v_count >= 2 then
    raise exception 'this space already has two people';
  end if;

  -- Whichever slot is free, never renumbering the person already here:
  -- `20260731230000:50` derives every row's A/B side from the slot.
  select s.slot
  into v_slot
  from (values (1::smallint), (2::smallint)) as s(slot)
  where not exists (
    select 1 from public.couple_members cm
    where cm.couple_id = v_couple
      and cm.member_slot = s.slot
  )
  order by s.slot
  limit 1;

  if v_slot is null then
    raise exception 'this space already has two people';
  end if;

  insert into public.couple_members (
    couple_id, profile_id, hue, member_slot
  ) values (
    v_couple, v_user, 'sage', v_slot
  );

  update public.invitations
  set consumed_at = now(), consumed_by = v_user
  where id = v_invitation.id;

  -- The mirror stops advertising a window that has been spent. The code
  -- itself is left in place: `join_code` is `not null`, and the pair who are
  -- now together have no further use for it either way.
  update public.couples
  set join_code_expires_at = null
  where id = v_couple;

  return json_build_object('couple_id', v_couple);
end;
$$;

revoke execute on function public.join_couple(text) from public, anon;
grant execute on function public.join_couple(text) to authenticated;

-- MARK: Creating a couple ------------------------------------------------
--
-- Unchanged from `20260725035142:345` except that the code it mints is now
-- backed by an invitation with a window. The returned shape is identical, so
-- `SupabaseRepository.createCouple` needs no change to keep working.

create or replace function public.create_couple()
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_couple uuid;
  v_code text;
begin
  if v_user is null then
    raise exception 'not signed in';
  end if;
  if (select public.my_couple_id()) is not null then
    raise exception 'already in a couple';
  end if;

  v_code := public.gen_join_code();
  insert into public.couples (join_code, join_code_expires_at, created_by)
  values (v_code, now() + private.invitation_window(), v_user)
  returning id into v_couple;

  insert into public.couple_members (
    couple_id, profile_id, hue, member_slot
  ) values (
    v_couple, v_user, 'burgundy', 1
  );

  insert into public.invitations (
    couple_id, code, created_by, expires_at
  ) values (
    v_couple, v_code, v_user, now() + private.invitation_window()
  );

  perform public.seed_couple_insights(v_couple);
  return json_build_object('couple_id', v_couple, 'join_code', v_code);
end;
$$;

revoke execute on function public.create_couple() from public, anon;
grant execute on function public.create_couple() to authenticated;

-- MARK: In-flight codes -----------------------------------------------------
--
-- Only for couples still waiting for somebody. A couple of two has no use for
-- an invitation and minting one would be handing out a key nobody asked for.

insert into public.invitations (couple_id, code, created_by, expires_at)
select
  c.id,
  c.join_code,
  c.created_by,
  now() + private.invitation_window()
from public.couples c
where (
  select count(*) from public.couple_members cm where cm.couple_id = c.id
) < 2
  and char_length(c.join_code) between 6 and 16
  and c.join_code = upper(c.join_code)
on conflict (code) do nothing;

update public.couples c
set join_code_expires_at = i.expires_at
from public.invitations i
where i.couple_id = c.id
  and i.consumed_at is null
  and i.revoked_at is null;

commit;
