-- When somebody actually made the outward move.
--
-- Life's "Waiting on someone else" band used to be decided by the verb in the
-- title: anything the app read as calling, messaging, emailing or booking was
-- filed as though a third party already had the next move. So "Call the
-- plumber", written down and never dialled, was reported back to the couple as
-- something a plumber was getting to. The app was asserting a fact about the
-- world that nobody had given it.
--
-- This column is that fact, and only a person can write it. The app already
-- asks — "You called them. Is that one done?" — after it opens the dialler,
-- and "not yet" is precisely the answer that means *I made the call and it is
-- still open*. Until now that answer was thrown away.
--
-- Opening another app is deliberately NOT what sets this. `openURL` returning
-- true says a dialler appeared, not that anybody spoke. The confirmation is the
-- person's own statement, which is why it is nullable and why it can be taken
-- back: `reached_out_at = null` returns the item to being ours to do.

alter table public.field_life_items
  add column if not exists reached_out_at timestamptz;

comment on column public.field_life_items.reached_out_at is
  'Set only from an explicit human confirmation that the outward act happened. '
  'Never inferred from opening another app. Null means the next move is still '
  'ours.';
