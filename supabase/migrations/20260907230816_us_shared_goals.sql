-- Goal content stays with its existing horizon. Votes are individual records,
-- matched against both a revision and the exact scope reviewed by the member.
alter table public.field_horizons add column goal_plan jsonb;
alter table public.field_horizons add constraint field_goal_plan_shape check (
  goal_plan is null or (
    jsonb_typeof(goal_plan) = 'object'
    and coalesce(jsonb_typeof(goal_plan->'revision') = 'string', false)
    and coalesce(length(goal_plan->>'revision') between 1 and 100, false)
    and coalesce(goal_plan->'approvedOwners' = '[]'::jsonb, false)
  )
);
create table public.field_goal_approvals (
  goal_id uuid not null references public.field_horizons(id) on delete cascade,
  couple_id uuid not null,
  profile_id uuid not null,
  revision text not null,
  commitment jsonb not null,
  created_at timestamptz not null default now(),
  primary key(goal_id, profile_id),
  foreign key(couple_id, profile_id) references public.couple_members(couple_id, profile_id) on delete cascade
);
alter table public.field_goal_approvals enable row level security;
create index field_goal_approvals_couple on public.field_goal_approvals(couple_id);
create policy goal_agreement_read on public.field_goal_approvals for select to authenticated using (
  couple_id = (select public.my_couple_id())
);
create view public.field_goal_current_approvals with (security_invoker = true) as
select a.* from public.field_goal_approvals a join public.field_horizons h
on h.id = a.goal_id and h.couple_id = a.couple_id
where h.goal_plan->>'revision' = a.revision
  and a.commitment = jsonb_build_array(h.title,h.thesis,h.window_label,
      h.goal_plan->'kind',h.goal_plan->'target',h.goal_plan->'currency');
revoke all on public.field_goal_current_approvals from anon, authenticated;
grant select on public.field_goal_current_approvals to authenticated;
create policy goal_agreement_insert on public.field_goal_approvals for insert to authenticated with check (
  profile_id = (select auth.uid()) and couple_id = (select public.my_couple_id()) and exists (
    select 1 from public.field_horizons h where h.id = goal_id and h.couple_id = field_goal_approvals.couple_id
      and h.goal_plan->>'revision' = revision
      and commitment = jsonb_build_array(h.title, h.thesis, h.window_label,
          h.goal_plan->'kind', h.goal_plan->'target', h.goal_plan->'currency')
  )
);
create policy goal_agreement_delete on public.field_goal_approvals for delete to authenticated using (
  profile_id = (select auth.uid()) and couple_id = (select public.my_couple_id())
);
revoke all on public.field_goal_approvals from anon, authenticated;
grant select, insert, delete on public.field_goal_approvals to authenticated;

create function public.set_us_goal_agreement(p_goal uuid, p_revision text, p_approved boolean)
returns void language plpgsql security invoker set search_path = '' as $$
declare h public.field_horizons;
begin
  select * into h from public.field_horizons where id = p_goal and couple_id = public.my_couple_id() for update;
  if not found or auth.uid() is null then raise exception 'Goal is unavailable'; end if;
  if h.goal_plan is null or h.goal_plan->>'revision' is distinct from p_revision then
    raise exception 'Goal has changed. Review it again.';
  end if;
  delete from public.field_goal_approvals where goal_id = p_goal and profile_id = auth.uid();
  if p_approved then
    insert into public.field_goal_approvals(goal_id,couple_id,profile_id,revision,commitment)
    values (h.id,h.couple_id,auth.uid(),p_revision,jsonb_build_array(h.title,h.thesis,h.window_label,
      h.goal_plan->'kind',h.goal_plan->'target',h.goal_plan->'currency'));
  end if;
end;
$$;
revoke all on function public.set_us_goal_agreement(uuid,text,boolean) from public, anon;
grant execute on function public.set_us_goal_agreement(uuid,text,boolean) to authenticated;
do $$ begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    alter publication supabase_realtime add table public.field_goal_approvals;
  end if;
end $$;
