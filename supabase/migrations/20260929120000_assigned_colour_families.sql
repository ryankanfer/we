-- Colours are assigned, not chosen.
--
-- The person who starts the couple is warm (burgundy by default) and the
-- person who joins is cool (sage by default). Each may pick a shade inside
-- their own family, never across. Two lights that are always different, and
-- an overlap that is always a third colour.
--
-- Rows from when either person could pick any of the eight are pulled back
-- into their family's default first, so the tighter constraints can land.

update public.field_identity
set swatch_a = case when swatch_a in ('burgundy', 'rose', 'rust', 'amber')
                    then swatch_a else 'burgundy' end,
    swatch_b = case when swatch_b in ('sage', 'moss', 'teal', 'indigo')
                    then swatch_b else 'sage' end
where swatch_a not in ('burgundy', 'rose', 'rust', 'amber')
   or swatch_b not in ('sage', 'moss', 'teal', 'indigo');

alter table public.field_identity
  drop constraint if exists field_identity_swatch_a_check,
  drop constraint if exists field_identity_swatch_b_check;

alter table public.field_identity
  add constraint field_identity_swatch_a_check
    check (swatch_a in ('burgundy', 'rose', 'rust', 'amber')),
  add constraint field_identity_swatch_b_check
    check (swatch_b in ('sage', 'moss', 'teal', 'indigo'));
