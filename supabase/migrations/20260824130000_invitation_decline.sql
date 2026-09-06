-- Declining. A ceremony that can only end in yes is a sales funnel.
--
-- Every path through the invitation so far leads to a couple. The person
-- holding the code can redeem it, or they can close the app and leave the
-- other person on a screen that says nothing is happening for seven days — and
-- between those two there is nothing. Saying no is not a failure mode of
-- saying yes, and it should be possible to decline an invitation to WE and
-- still think well of it.
--
-- WHAT DECLINING DOES
--
-- It revokes the invitation, which is exactly what the inviter's own withdraw
-- does, by exactly the same route: the row is marked revoked and the mirror on
-- `couples` stops advertising a code that would be refused. There is no
-- decline table, no decline column, and no record that a decline is what
-- happened. A revoked invitation is a revoked invitation.
--
-- That absence is the design. A stored decline is a fact about somebody who
-- deliberately did not join, held in a space they never entered, and the only
-- thing anybody could ever do with it is show it to the person who was turned
-- down.
--
-- WHY THE CODE IS THE AUTHORISATION
--
-- The person declining has no account, no session, and no membership of the
-- couple whose invitation this is — the same position they are in when they
-- read who is waiting for them. Holding the code is what makes them the
-- invited person, here as everywhere else in this flow.
--
-- The write is deliberately narrower than the read it accompanies: it can only
-- ever move a live invitation to revoked. It cannot consume one, cannot create
-- one, cannot touch a couple's membership, and returns nothing at all, so it
-- reports neither success nor failure. Calling it twice is calling it once.
--
-- WHAT THE OTHER PERSON SEES
--
-- Their invitation screen, on a natural return, saying the invitation is
-- closed. Not who closed it, not when, not why, and no notification: being
-- interrupted to be told no is worse than finding out quietly. The copy is in
-- `WEGateCopy` and must not attribute — nobody owes an account of themselves
-- for having declined.

begin;

create or replace function public.decline_invitation(p_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid;
begin
  -- Live only. A spent code must not be revocable by whoever still has a copy
  -- of it: the couple it opened is two people by then, and this would be a
  -- stranger reaching into their space.
  update public.invitations
  set revoked_at = now()
  where code = upper(trim(p_code))
    and consumed_at is null
    and revoked_at is null
    and expires_at > now()
  returning couple_id into v_couple;

  if v_couple is null then
    return;
  end if;

  -- The same mirror maintenance as `revoke_invitation`. `join_code` is
  -- `not null unique`, so it takes a fresh value that opens nothing rather
  -- than nothing at all; the null expiry is what tells the client there is no
  -- invitation to display.
  update public.couples
  set join_code = public.gen_join_code(),
      join_code_expires_at = null
  where id = v_couple;
end;
$$;

-- `anon`, for the same reason as `invitation_greeting`: the person this is for
-- has no account, and requiring them to make one in order to say no would be
-- the worst possible reading of what an invitation is.
revoke all on function public.decline_invitation(text) from public;
grant execute on function public.decline_invitation(text) to anon, authenticated;

commit;
