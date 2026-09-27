-- hold_until is cleared the moment a row stops being private.
begin;

create extension if not exists pgtap with schema extensions;

select plan(3);

select has_column('public', 'field_life_items', 'hold_until',
  'field_life_items has hold_until');

select has_trigger('public', 'field_life_items', 'zz_field_life_items_clear_hold',
  'the clear on share trigger exists');

select function_returns('private', 'field_clear_hold_on_share', 'trigger',
  'the clearing function is a trigger function');

select * from finish();
rollback;
