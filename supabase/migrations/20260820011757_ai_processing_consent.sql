begin;

-- A selected answer is personal content. The worker may send it to OpenAI only
-- when the owner gave permission for this exact submission. The timestamp is
-- kept on the owner-only response row so permission travels with the payload
-- and can be checked again at every server boundary.
alter table public.responses
  add column if not exists ai_processing_consented_at timestamptz,
  add column if not exists ai_processing_consent_version text;

alter table public.journey_response_receipts
  add column if not exists ai_processing_consented_at timestamptz,
  add column if not exists ai_processing_consent_version text;

comment on column public.responses.ai_processing_consented_at is
  'Owner consent for OpenAI processing of this submitted choice.';
comment on column public.responses.ai_processing_consent_version is
  'Disclosure version accepted for OpenAI processing.';
comment on column public.journey_response_receipts.ai_processing_consented_at is
  'Content-free audit timestamp for explicit OpenAI processing consent.';
comment on column public.journey_response_receipts.ai_processing_consent_version is
  'Content-free disclosure version accepted for OpenAI processing.';

-- Pre-consent builds could have left answers or jobs behind. They cannot be
-- grandfathered into third-party processing. Returning those questions to an
-- unanswered state is safer and clearer than holding them forever.
delete from public.journey_synthesis_jobs j
where exists (
  select 1 from public.responses r
  where r.insight_id = j.insight_id
    and r.ai_processing_consented_at is null
);

delete from public.journey_response_receipts rr
where exists (
  select 1 from public.responses r
  where r.insight_id = rr.insight_id
    and r.profile_id = rr.profile_id
    and r.ai_processing_consented_at is null
);

delete from public.responses r
where r.ai_processing_consented_at is null
  and exists (
    select 1 from public.insights i
    where i.id = r.insight_id and i.journey_scope is not null
  );

revoke execute on function public.submit_response(uuid,text,text)
  from public, anon, authenticated;
drop function public.submit_response(uuid,text,text);

create function public.submit_response(
  p_insight uuid,
  p_choice text,
  p_ai_processing_consent boolean,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.insight_consent;
  v_couple uuid;
  v_submitted_with_consent integer;
begin
  if p_ai_processing_consent is not true then
    raise exception 'OpenAI processing permission is required';
  end if;

  v_couple := public.assert_my_insight(p_insight);
  select * into c from public.insight_consent
  where insight_id = p_insight for update;

  if c.visibility <> 'mutual' or c.readiness <> 'accepted' then
    raise exception 'question is not open';
  end if;
  if not exists (
    select 1 from public.insights i
    where i.id = p_insight
      and i.present
      and (i.expires_at is null or i.expires_at > now())
      and p_choice = any(i.options)
  ) then raise exception 'answer is not available'; end if;
  if p_note is not null and char_length(p_note) > 1200 then
    raise exception 'private note is too long';
  end if;
  if exists (
    select 1 from public.responses
    where insight_id = p_insight
      and profile_id = (select auth.uid())
      and status = 'submitted'
  ) then raise exception 'already submitted'; end if;

  insert into public.responses (
    insight_id, profile_id, status, choice, note,
    ai_processing_consented_at, ai_processing_consent_version, updated_at
  ) values (
    p_insight, (select auth.uid()), 'submitted', p_choice,
    nullif(btrim(p_note), ''), now(), '2026-08-20', now()
  )
  on conflict (insight_id, profile_id) do update
  set status = 'submitted', choice = excluded.choice,
      note = excluded.note,
      ai_processing_consented_at = excluded.ai_processing_consented_at,
      ai_processing_consent_version = excluded.ai_processing_consent_version,
      updated_at = now();

  insert into public.journey_response_receipts (
    insight_id, profile_id, submitted_at, resolved_at,
    ai_processing_consented_at, ai_processing_consent_version
  ) values (
    p_insight, (select auth.uid()), now(), null, now(), '2026-08-20'
  )
  on conflict (insight_id, profile_id) do update
  set submitted_at = excluded.submitted_at,
      resolved_at = null,
      ai_processing_consented_at = excluded.ai_processing_consented_at,
      ai_processing_consent_version = excluded.ai_processing_consent_version;

  delete from public.journey_passes
  where insight_id = p_insight and profile_id = (select auth.uid());
  perform private.record_journey_event(p_insight, 'answered');

  select count(*)::integer into v_submitted_with_consent
  from public.responses
  where insight_id = p_insight
    and status = 'submitted'
    and ai_processing_consented_at is not null
    and ai_processing_consent_version = '2026-08-20';

  if v_submitted_with_consent >= 2 then
    insert into public.journey_synthesis_jobs (insight_id, couple_id)
    values (p_insight, v_couple)
    on conflict (insight_id) do nothing;
  end if;
end;
$$;

revoke execute on function public.submit_response(uuid,text,boolean,text)
  from public, anon;
grant execute on function public.submit_response(uuid,text,boolean,text)
  to authenticated;

-- Defense in depth: even a manually inserted job cannot be claimed until two
-- consent-bearing submitted responses exist.
create or replace function public.claim_journey_synthesis_jobs(p_limit integer)
returns table (insight_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  with candidates as (
    select j.insight_id
    from public.journey_synthesis_jobs j
    where j.status = 'queued'
      and j.available_at <= now()
      and (
        select count(*)
        from public.responses r
        where r.insight_id = j.insight_id
          and r.status = 'submitted'
          and r.ai_processing_consented_at is not null
          and r.ai_processing_consent_version = '2026-08-20'
      ) = 2
    order by j.created_at
    for update skip locked
    limit greatest(1, least(coalesce(p_limit, 10), 25))
  ), claimed as (
    update public.journey_synthesis_jobs j
    set status = 'processing', claimed_at = now(), updated_at = now()
    from candidates c
    where j.insight_id = c.insight_id
    returning j.insight_id
  )
  select claimed.insight_id from claimed;
end;
$$;

revoke execute on function public.claim_journey_synthesis_jobs(integer)
  from public, anon, authenticated;
grant execute on function public.claim_journey_synthesis_jobs(integer)
  to service_role;

commit;
