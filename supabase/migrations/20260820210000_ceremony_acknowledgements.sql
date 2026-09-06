-- The Joining, made durable.
--
-- The ceremony is three Promise beats performed on two phones at once, where
-- neither screen advances until both people have acknowledged the beat. Held
-- entirely in memory, that breaks the first time either person locks a phone
-- — and screen 12, one person away for a day, is the state most likely to
-- occur in real use rather than the least. So an acknowledgement is written
-- down, and the ceremony resumes on the beat it was left on.
--
-- WHAT MAY NOT LEAK
--
-- "Nothing reports on the other person's timing, ever." Held has to feel like
-- patience rather than like waiting for a server, and any accumulating signal
-- converts devotion into anxiety. That rules out more than a visible
-- timestamp: it rules out the partner being *able* to derive one.
--
-- Three mechanisms, and the order matters:
--
--   1. RLS is owner-only for select. There is no policy under which either
--      person can read the other's row, so the raw acknowledgement and its
--      `acknowledged_at` are unreadable across the pair by construction
--      rather than by anybody remembering not to query them.
--
--   2. The only partner-visible read is `ceremony_beat_is_kept`, which
--      returns a bare boolean per beat. No identity, no ordering, no count,
--      no timestamp. A caller cannot distinguish "neither of us has acted"
--      from "I have acted and they have not" from the aggregate alone — and
--      it already knows its own half locally, so it learns exactly one bit:
--      whether the beat is done.
--
--   3. The table is deliberately absent from
--      `FieldSupabaseBackend.observedTables`, so a write generates no
--      realtime row event on the partner's subscription. The partner learns
--      "both ready" by re-reading the aggregate on a presence tick. A
--      row-level event would carry its own arrival time, which is the
--      timestamp again wearing a different hat.
--
-- Point 3 is why this is not simply another field table. Points 1 and 2 would
-- be undone by publishing it.

create table if not exists public.ceremony_acknowledgements (
  couple_id uuid not null references public.couples(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  -- The beat, by name rather than by index. An integer would invite reading
  -- "how far along is the other person" out of a maximum, and names survive
  -- the beats being reordered.
  beat text not null,
  acknowledged_at timestamptz not null default now(),
  primary key (couple_id, profile_id, beat),
  constraint ceremony_acknowledgements_beat_known
    check (beat in ('yours_stays_yours', 'nothing_moves_without_you',
                    'what_opens_opens_together'))
);

alter table public.ceremony_acknowledgements enable row level security;

-- Select and insert, own rows only. There is deliberately no update and no
-- delete: an acknowledgement is a thing that happened, and a promise you can
-- retract on your own is not one.
drop policy if exists ceremony_acknowledgements_select_own
  on public.ceremony_acknowledgements;
create policy ceremony_acknowledgements_select_own
  on public.ceremony_acknowledgements for select to authenticated
  using (profile_id = (select auth.uid()));

drop policy if exists ceremony_acknowledgements_insert_own
  on public.ceremony_acknowledgements;
create policy ceremony_acknowledgements_insert_own
  on public.ceremony_acknowledgements for insert to authenticated
  with check (
    profile_id = (select auth.uid())
    and couple_id = (select public.my_couple_id())
  );

grant select, insert on public.ceremony_acknowledgements to authenticated;

-- MARK: The only thing the other person can see ----------------------------

-- One boolean per beat: kept, or not kept.
--
-- `security definer` because it must read rows RLS forbids the caller to see,
-- and that is the whole point — it reads both people's rows and returns
-- neither. The couple is resolved from the caller's own membership rather
-- than taken as an argument, so there is no couple id to guess at.
--
-- Returns a row per known beat, including beats nobody has touched, so the
-- client can land on the first unkept beat without inferring anything from
-- which rows are missing.
create or replace function public.ceremony_beat_is_kept()
returns table (beat text, kept boolean)
language sql
security definer
set search_path = public
stable
as $$
  with couple as (
    select public.my_couple_id() as id
  ),
  members as (
    -- Membership is the live row set: departure removes the row rather than
    -- flagging it, which is what lets a beat resolve for a survivor instead
    -- of stranding them waiting on somebody who has gone.
    select count(*)::int as n
    from public.couple_members cm, couple c
    where cm.couple_id = c.id
  ),
  beats(beat) as (
    values ('yours_stays_yours'),
           ('nothing_moves_without_you'),
           ('what_opens_opens_together')
  )
  select
    b.beat,
    -- A beat is kept when every active member has acknowledged it. Comparing
    -- against the live membership rather than a hard-coded two means a couple
    -- mid-departure cannot be stranded on a beat waiting for somebody who is
    -- no longer there.
    (
      select count(*)
      from public.ceremony_acknowledgements a, couple c
      where a.couple_id = c.id and a.beat = b.beat
    ) >= (select n from members)
    and (select n from members) > 0 as kept
  from beats b;
$$;

revoke all on function public.ceremony_beat_is_kept() from public;
grant execute on function public.ceremony_beat_is_kept() to authenticated;

-- MARK: Keeping a beat -----------------------------------------------------

-- Insert-only and idempotent. Re-acknowledging is not an error: a phone that
-- loses its connection mid-beat should be able to say the same thing again
-- without being told it already did, and `on conflict do nothing` keeps the
-- original `acknowledged_at` rather than refreshing it into something newer.
create or replace function public.keep_ceremony_beat(p_beat text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple uuid;
begin
  v_couple := public.my_couple_id();
  if v_couple is null then
    raise exception 'no couple';
  end if;

  insert into public.ceremony_acknowledgements (couple_id, profile_id, beat)
  values (v_couple, auth.uid(), p_beat)
  on conflict (couple_id, profile_id, beat) do nothing;
end;
$$;

revoke all on function public.keep_ceremony_beat(text) from public;
grant execute on function public.keep_ceremony_beat(text) to authenticated;
