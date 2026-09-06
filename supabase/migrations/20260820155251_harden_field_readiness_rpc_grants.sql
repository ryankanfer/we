begin;

-- PostgreSQL grants EXECUTE on new functions to PUBLIC unless it is revoked
-- explicitly. These RPCs are authenticated app surfaces; an anonymous caller
-- must never reach their SECURITY DEFINER bodies, even though the bodies also
-- resolve the caller through auth.uid().
revoke all on function public.field_readiness_mark(date)
  from public, anon;
revoke all on function public.field_readiness_state(date)
  from public, anon;

grant execute on function public.field_readiness_mark(date)
  to authenticated;
grant execute on function public.field_readiness_state(date)
  to authenticated;

commit;
