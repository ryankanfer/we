-- Whether this couple performs The Joining at all.
--
-- WHY THIS IS NOT DERIVED FROM THE ACKNOWLEDGEMENTS
--
-- The obvious implementation of "has this couple finished the ceremony" reads
-- `ceremony_beat_is_kept()` and treats "no beat kept" as "not started". That
-- is correct for a couple who arrived after the ceremony existed, and wrong
-- for every couple who arrived before it: they have no acknowledgement rows
-- either, so the obvious implementation walks all of them into a ceremony on
-- their next launch, months into a relationship, as though they had just met.
--
-- Absence of rows means "nothing was written here", and that is all it means.
-- Whether anything *should* have been written is a different fact, so it is
-- stored as a different fact.
--
-- WHY NOT BACKFILL THE ROWS INSTEAD
--
-- Writing three acknowledgement rows for every existing couple would make the
-- aggregate report a promise that nobody made. The acknowledgements table is
-- explicit that this is not what it holds: "there is deliberately no update
-- and no delete: an acknowledgement is a thing that happened, and a promise
-- you can retract on your own is not one." A promise you never made is worse
-- than one you can retract, and the ceremony's whole claim is that both people
-- performed it. Forging the evidence to simplify a boolean would be the one
-- lie the feature cannot afford.
--
-- So eligibility is two independent facts, and only the second one lives in
-- `ceremony_acknowledgements`:
--
--   1. does this couple perform the ceremony  (here)
--   2. how far has it got                     (the aggregate)

-- Added as `false` so that every couple that already exists is backfilled to
-- "does not perform it" by the act of adding the column, rather than by a
-- separate statement that has to be got right. The default then flips to
-- `true`, which is what every couple created from here on takes.
--
-- Written this way round on purpose: `add column default true` followed by
-- `update ... set false` would be correct exactly once, and would silently
-- un-require the ceremony for genuinely new couples if the migration were
-- ever replayed. This form is idempotent.
alter table public.couples
  add column if not exists ceremony_required boolean not null default false;

alter table public.couples
  alter column ceremony_required set default true;

comment on column public.couples.ceremony_required is
  'Whether this couple performs The Joining. False for couples that predate '
  'the ceremony, who are complete by construction rather than by assertion.';

-- MARK: The only thing a client asks ---------------------------------------

-- One boolean, for the caller's own couple.
--
-- `security definer` and no argument, for the same reasons as
-- `ceremony_beat_is_kept()`: the couple is resolved from the caller's own
-- membership rather than taken as a parameter, so there is no couple id to
-- guess at and no way to ask this question about somebody else's relationship.
--
-- Returns false rather than null when there is no couple. A person with no
-- couple has nobody to perform a ceremony with, and a null here would only
-- push a three-way decision into every caller for a case that means "no".
create or replace function public.ceremony_is_required()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    (
      select c.ceremony_required
      from public.couples c
      where c.id = public.my_couple_id()
    ),
    false
  );
$$;

revoke all on function public.ceremony_is_required() from public;
grant execute on function public.ceremony_is_required() to authenticated;
