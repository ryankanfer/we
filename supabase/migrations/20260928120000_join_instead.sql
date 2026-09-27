-- Join instead: the answer to both people tapping "Invite them".
--
-- WHY
--
-- A couple is made by one person creating a space and the other joining it.
-- If both create one before either joins, each is alone in a space of their
-- own and `join_couple` refuses both of them ('already in a couple'). The
-- only way out was deleting an account.
--
-- WHAT
--
-- `public.join_instead(p_code)` lets somebody who is *alone* in their space
-- give it up and join the other person's. It is narrow on purpose:
--
--   * the caller's space must have exactly one member, themselves. A space
--     with two people is a relationship and is never dissolved from here;
--   * the code must be a live invitation to a *different* space, checked
--     before anything is removed, so a bad code costs nothing;
--   * the caller's own space is deleted whole. Everything in it cascades
--     from the couple, exactly as it does when a solo account is deleted
--     (`private.delete_my_account`), and the app says so before asking;
--   * the join itself is `public.join_couple`, unchanged, in the same
--     transaction. Either both happen or neither does.

begin;

create or replace function public.join_instead(p_code text)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_code text := upper(trim(p_code));
  v_mine uuid;
  v_members integer;
  v_target uuid;
begin
  if v_user is null then
    raise exception 'not signed in';
  end if;

  v_mine := (select public.my_couple_id());
  if v_mine is null then
    return public.join_couple(p_code);
  end if;

  perform 1 from public.couples where id = v_mine for update;

  select count(*) into v_members
  from public.couple_members cm
  where cm.couple_id = v_mine;

  if v_members <> 1 then
    raise exception 'you already share a space';
  end if;

  select i.couple_id into v_target
  from public.invitations i
  where i.code = v_code
    and i.revoked_at is null
    and i.consumed_at is null
    and i.expires_at > now();

  if v_target is null then
    raise exception 'that invitation is no longer open';
  end if;
  if v_target = v_mine then
    raise exception 'that is your own invitation';
  end if;

  delete from public.couples where id = v_mine;

  return public.join_couple(p_code);
end;
$$;

revoke all on function public.join_instead(text) from public, anon;
grant execute on function public.join_instead(text) to authenticated;

commit;
