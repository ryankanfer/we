-- Onboarding 6f: the three questions.
--
-- "Three questions and a calendar is the entire cold start. Resist adding
-- fields — low barrier to entry is an explicit product requirement, and the
-- intelligence is supposed to earn its knowledge by observation."
--
-- They live on field_identity rather than in a table of their own because
-- they are singular per couple and answered once, at setup. A table would
-- imply a history the product does not keep.
--
-- All three are nullable on purpose: every question is skippable, and a
-- skipped question has to be distinguishable from an empty answer.

alter table public.field_identity
  add column if not exists lives_together boolean,
  add column if not exists saving_for text,
  add column if not exists looks_after text;

comment on column public.field_identity.lives_together is
  'Do you live together? Null when skipped.';
comment on column public.field_identity.saving_for is
  'What is the one thing you are saving for? Null when skipped.';
comment on column public.field_identity.looks_after is
  'Who or what else do you look after? Null when skipped.';

-- Bounded so a paste cannot become an essay. These feed the intelligence's
-- reasoning lines, which are one sentence.
alter table public.field_identity
  drop constraint if exists field_identity_saving_for_length;
alter table public.field_identity
  add constraint field_identity_saving_for_length
  check (saving_for is null or char_length(saving_for) <= 200);

alter table public.field_identity
  drop constraint if exists field_identity_looks_after_length;
alter table public.field_identity
  add constraint field_identity_looks_after_length
  check (looks_after is null or char_length(looks_after) <= 200);

-- RLS already covers this table couple-wide from 20260730120000_field_zones;
-- new columns inherit those policies, so nothing further is needed here.
