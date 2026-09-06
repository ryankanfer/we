-- Who is waiting, told to the person holding the invitation.
--
-- WHY THIS EXISTS
--
-- The invited person's first screen cannot be the inviter's first screen. Ryan
-- arrived through curiosity and was asked a question; Dylan arrived because he
-- is wanted, and should be told rather than asked:
--
--   Ryan is waiting.
--
-- One line, Ryan's hue behind it. Which means the app has to know Ryan's name
-- and hue at a moment when Dylan has no account, no session, and no couple —
-- so no existing read path can answer it. Every one of them is scoped by
-- `my_couple_id()`, and Dylan is not a member of anything yet.
--
-- WHAT THIS DISCLOSES, AND TO WHOM
--
-- A first name and a colour, to whoever holds a live invitation code. That is
-- not a new disclosure: the invitation screen already promises it in as many
-- words — "They'll see your name and nothing else" — and this is the first
-- code path that makes the promise true rather than deferring it until after
-- redemption.
--
-- The code is the credential. `gen_join_code()` returns sixteen hex characters
-- from `gen_random_bytes(8)`, so guessing one is guessing sixty four bits;
-- there is no enumeration to defend against here that redemption itself is not
-- already exposed to. The match is exact and whole: no prefix, no similarity,
-- nothing that would let a near miss confirm a real code.
--
-- WHAT IT MUST NOT DISCLOSE
--
--   · nothing about the couple beyond one member's name and hue
--   · no id of any kind, so the answer cannot be joined to anything else
--   · no timing: not when the invitation was made, not when it expires, not
--     whether it *recently* expired. A dead code and a code that never existed
--     return exactly the same thing, which is nothing.
--
-- That last one is why this returns null rather than raising. `join_couple`
-- deliberately distinguishes its four refusals — retyping a code that was
-- never going to work is its own small cruelty — but it does so for someone
-- who has already committed to redeeming. A screen that merely greets has no
-- business reporting on the state of somebody else's invitation.

begin;

create or replace function public.invitation_greeting(p_code text)
returns json
language sql
stable
security definer
set search_path = ''
as $$
  select json_build_object('name', p.name, 'hue', cm.hue)
  from public.invitations i
  join public.couple_members cm
    on cm.couple_id = i.couple_id
   and cm.profile_id = i.created_by
  join public.profiles p
    on p.id = i.created_by
  where i.code = upper(trim(p_code))
    and i.consumed_at is null
    and i.revoked_at is null
    and i.expires_at > now()
  limit 1;
$$;

-- `anon` deliberately. The person this answers is, by definition, someone
-- without an account: they are reading the line that comes *before* they make
-- one. Authenticated callers get it too, for the person who signed up first
-- and pasted the code afterwards.
revoke all on function public.invitation_greeting(text) from public;
grant execute on function public.invitation_greeting(text) to anon, authenticated;

commit;
