-- Recurring shared moments for the immersive WE landing surface.
-- Each person answers privately. Existing response RLS continues to reveal
-- answers only after both have submitted.

create unique index if not exists insights_couple_seed_key_idx
  on public.insights(couple_id, seed_key);

create or replace function public.refresh_shared_moments(p_local_date date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_couple uuid := (select public.my_couple_id());
  v_today_key text;
  v_week_key text;
  v_active_load int;
  v_next_plan public.plans;
begin
  if v_couple is null then
    return;
  end if;

  if p_local_date is null
     or p_local_date < current_date - 1
     or p_local_date > current_date + 1 then
    raise exception 'local date is outside the allowed window';
  end if;

  v_today_key := 'tonight-' || to_char(p_local_date, 'YYYYMMDD');
  v_week_key := to_char(p_local_date, 'IYYY-IW');

  update public.insights i
  set present = false
  where i.couple_id = v_couple
    and i.seed_key like 'tonight-%'
    and i.seed_key <> v_today_key;

  insert into public.insights (
    couple_id, seed_key, kind, domain, present, title, body,
    evidence, source, options, sort
  ) values (
    v_couple,
    v_today_key,
    'logistical',
    'us',
    true,
    'How should tonight feel?',
    'Choose separately. WE will look for a shared direction without exposing either answer.',
    'A small check-in for this evening.',
    'A moment for tonight',
    array[
      'Quiet and close',
      'Easy, with no decisions',
      'Out of the house',
      'Playful and spontaneous',
      'Room to recharge'
    ],
    -300
  )
  on conflict (couple_id, seed_key) do update
  set present = true,
      sort = excluded.sort;

  insert into public.insights (
    couple_id, seed_key, kind, domain, present, title, body,
    evidence, source, options, sort
  ) values (
    v_couple,
    'weekend-' || v_week_key,
    'logistical',
    'us',
    true,
    'What should this weekend hold?',
    'Choose the shape you are quietly hoping for. WE will find the part that can belong to both of you.',
    'A little intention before the calendar fills itself.',
    'Your shared rhythm',
    array[
      'Mostly rest',
      'Something new',
      'Clear one unfinished thing',
      'See people we love',
      'Keep it unplanned'
    ],
    -200
  )
  on conflict (couple_id, seed_key) do update
  set present = true,
      sort = excluded.sort;

  select count(*)
  into v_active_load
  from public.responsibilities r
  where r.couple_id = v_couple
    and r.status = 'active';

  if v_active_load > 0 then
    insert into public.insights (
      couple_id, seed_key, kind, domain, present, title, body,
      evidence, source, options, sort
    ) values (
      v_couple,
      'load-' || v_week_key,
      'logistical',
      'life',
      true,
      'What would make this week feel lighter?',
      'Answer privately. WE will suggest one adjustment without turning care into a score.',
      format(
        '%s active %s are currently being carried.',
        v_active_load,
        case when v_active_load = 1 then 'responsibility' else 'responsibilities' end
      ),
      'Life · current shared load',
      array[
        'I can take one thing',
        'Let''s do one thing together',
        'Decide what can wait',
        'Keep the roles as they are',
        'Ask me directly where I have room'
      ],
      -100
    )
    on conflict (couple_id, seed_key) do update
    set present = true,
        evidence = excluded.evidence,
        sort = excluded.sort;
  end if;

  select p.*
  into v_next_plan
  from public.plans p
  where p.couple_id = v_couple
    and p.status = 'active'
    and p.scheduled_on is not null
    and p.scheduled_on >= p_local_date
  order by p.scheduled_on
  limit 1;

  if v_next_plan.id is not null then
    insert into public.insights (
      couple_id, seed_key, kind, domain, present, title, body,
      evidence, source, options, sort
    ) values (
      v_couple,
      'plan-' || v_next_plan.id::text,
      'logistical',
      'us',
      true,
      format('How should “%s” feel?', v_next_plan.title),
      'The plan already exists. This is about the quality you want to protect inside it.',
      format('Coming up on %s.', to_char(v_next_plan.scheduled_on, 'FMMonth FMDD')),
      'Ahead · next shared plan',
      array[
        'Calm and spacious',
        'A little special',
        'Simple and practical',
        'Open to surprise'
      ],
      -50
    )
    on conflict (couple_id, seed_key) do update
    set present = true,
        title = excluded.title,
        evidence = excluded.evidence,
        sort = excluded.sort;
  end if;

  insert into public.insight_consent (
    insight_id, visibility, readiness, accepted_at
  )
  select
    i.id, 'mutual', 'accepted', now()
  from public.insights i
  where i.couple_id = v_couple
    and (
      i.seed_key = v_today_key
      or i.seed_key = 'weekend-' || v_week_key
      or i.seed_key = 'load-' || v_week_key
      or (
        v_next_plan.id is not null
        and i.seed_key = 'plan-' || v_next_plan.id::text
      )
    )
  on conflict (insight_id) do nothing;
end;
$$;

revoke execute on function public.refresh_shared_moments(date)
  from public, anon;
grant execute on function public.refresh_shared_moments(date)
  to authenticated;
