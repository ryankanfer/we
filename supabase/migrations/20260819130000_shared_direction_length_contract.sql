begin;

-- The synthesis worker and the table it writes to disagreed about length.
--
-- `complete_journey_synthesis` validates a summary at 1..240 and a rationale at
-- 1..500 — the same bounds `synthesisSchema` enforces on the model — and then
-- inserts them into `shared_directions.title` and `.message`, which were still
-- capped at 120 and 240 from `20260729193000_private_answers_shared_directions`.
--
-- A summary of 121..240 characters is legal at every layer that checks it and
-- then violates a constraint on insert. The worker catches the exception, fails
-- the job, and after two attempts the couple is handed "Let this rest" — the
-- same copy a genuinely unsafe synthesis produces. The failure is invisible on
-- both sides: the couple cannot tell a broken system from a careful one, and
-- nothing in the suite caught it because every fixture used short strings.
--
-- Widening rather than clamping: truncating a direction mid-sentence would put
-- copy in front of both people that the model did not write and no one
-- reviewed. Every existing row satisfies the wider bound, so this is safe to
-- apply forward.

alter table public.shared_directions
  drop constraint if exists shared_directions_title_check;
alter table public.shared_directions
  add constraint shared_directions_title_check
  check (char_length(title) between 1 and 240);

alter table public.shared_directions
  drop constraint if exists shared_directions_message_check;
alter table public.shared_directions
  add constraint shared_directions_message_check
  check (char_length(message) between 1 and 500);

-- Defense in depth the new `private.*` functions were missing.
--
-- Schema `private` already has `usage` revoked, so this is not currently
-- reachable — but every other `private.*` function carries an explicit revoke,
-- and a function that silently relies on the schema grant is one `grant usage`
-- away from being callable.
--
-- Blanket rather than enumerated, deliberately.
--
-- Naming each signature meant this migration only applied cleanly against a
-- database whose `private` schema matched this checkout exactly — and
-- `20260808120000` was still being edited, so that was not true everywhere.
-- Enumerating also means every future `private.*` function has to remember to
-- add itself here, which is the kind of rule that is followed for a while.
--
-- Nothing in `private` is meant to be callable by a client under any
-- circumstances, so the blanket form states the actual intent and cannot fail
-- on a signature that happens not to exist yet.
revoke all on all functions in schema private
  from public, anon, authenticated;

-- And for anything added later, without needing a migration to remember.
alter default privileges in schema private
  revoke all on functions from public, anon, authenticated;

commit;
