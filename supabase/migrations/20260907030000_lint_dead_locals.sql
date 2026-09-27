-- Two locals nothing reads, in two `security definer` RPCs.
--
-- `db lint --fail-on warning` had never run against a complete schema: the
-- lane died applying 20260820161957 long before it, so these sat unreported.
-- Both are dead bindings, not dropped checks, and this migration removes them
-- without touching what either function does.
--
--   confirm_contextual_suggestion  `v_user := auth.uid()` was never read.
--                                  Authorisation is the `my_couple_id()`
--                                  scoping on the first select plus
--                                  `private.assert_v2_member`, both still here.
--   pass_journey_question          `v_couple := public.assert_my_insight(...)`
--                                  bound a return value nothing reads. The
--                                  call is the check; it becomes `perform`.
--
-- The two remaining lint findings are deliberate and are recorded in
-- scripts/qa/run-supabase-contract.sh rather than changed here.

begin;

create or replace function public.confirm_contextual_suggestion(
  p_suggestion uuid,
  p_title text,
  p_note text default null,
  p_owner uuid default null,
  p_scheduled_on date default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_suggestion public.contextual_suggestions%rowtype;
  v_responsibility uuid;
begin
  select s.* into v_suggestion
  from public.contextual_suggestions s
  where s.id = p_suggestion
    and s.couple_id = (select public.my_couple_id())
    and s.is_eligible;
  if v_suggestion.id is null then
    raise exception 'suggestion is no longer available';
  end if;
  perform private.assert_v2_member(v_suggestion.couple_id);
  perform private.lock_relationship(v_suggestion.couple_id);
  select s.* into v_suggestion
  from public.contextual_suggestions s
  where s.id = p_suggestion
  for update;
  if v_suggestion.confirmed_responsibility_id is not null then
    return v_suggestion.confirmed_responsibility_id;
  end if;
  if p_owner is not null
     and not exists (
       select 1 from public.couple_members cm
       where cm.couple_id = v_suggestion.couple_id
         and cm.profile_id = p_owner
     ) then
    raise exception 'responsibility owner is not in this WE space';
  end if;
  select r.id into v_responsibility
  from public.responsibilities r
  where r.couple_id = v_suggestion.couple_id
    and r.related_plan_id = v_suggestion.related_plan_id
    and r.status = 'active'
  limit 1;
  if v_responsibility is null then
    insert into public.responsibilities (
      couple_id,
      title,
      note,
      owner_id,
      scheduled_on,
      related_plan_id,
      suggestion_provenance
    ) values (
      v_suggestion.couple_id,
      trim(p_title),
      p_note,
      p_owner,
      p_scheduled_on,
      v_suggestion.related_plan_id,
      v_suggestion.provenance
    ) returning id into v_responsibility;
  end if;
  update public.contextual_suggestions
  set confirmed_responsibility_id = v_responsibility
  where id = p_suggestion;
  return v_responsibility;
end;
$$;

create or replace function public.pass_journey_question(p_insight uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- The call is the authorisation. Nothing reads the couple it
  -- returns, so nothing binds it.
  perform public.assert_my_insight(p_insight);
  if not exists (
    select 1 from public.insights
    where id = p_insight and journey_scope is not null and present
  ) then raise exception 'question is not active'; end if;

  insert into public.journey_passes (insight_id, profile_id)
  values (p_insight, (select auth.uid()))
  on conflict (insight_id, profile_id) do nothing;
end;
$$;

commit;
