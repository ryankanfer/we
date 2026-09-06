begin;

-- A journey's subjects accumulate over its life.
--
-- `confirm_shared_direction` copied the insight's single trigger reference into
-- `field_journeys.subject_references` and never touched it again. One reference
-- is all a journey ever held, while `SharedJourneyCapabilityPolicy` earns the
-- criteria surface at three — so the surface could never appear, and the room
-- read "this journey is still taking shape" permanently. Nothing logged,
-- because a reference that resolves to nothing is dropped by design.
--
-- The linkage this needs already exists: `field_life_items.journey_id` and
-- `field_evidence.journey_id` are both written at confirmation, and both kinds
-- already resolve on the client. So subjects are not invented here — they are
-- read back from what the journey has actually gathered.
--
-- Rebuild rather than append: it is idempotent, it drops references to rows the
-- couple has since deleted, and it cannot accumulate duplicates on a retry.

create or replace function private.refresh_journey_subjects(p_journey uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_refs jsonb;
begin
  select
    -- The trigger the question grew from, first and always, so provenance
    -- reads in the order the journey actually happened.
    coalesce(
      (select i.subject_references
       from public.field_journeys j
       join public.insights i on i.id = j.insight_id
       where j.id = p_journey),
      '[]'::jsonb
    )
    ||
    -- Then the shared evidence this journey carries.
    coalesce(
      (select jsonb_agg(
                jsonb_build_object('kind', 'evidence', 'id', e.id::text)
                order by e.occurred_at, e.id
              )
       from public.field_evidence e
       where e.journey_id = p_journey and e.owner = 'shared'),
      '[]'::jsonb
    )
    ||
    -- Then the Life the journey put into the world. `visibility` is filtered
    -- here as well as on the client: a private item must not become a shared
    -- subject even for a moment, and the client filter is not the only place
    -- that rule should be true.
    coalesce(
      (select jsonb_agg(
                jsonb_build_object('kind', 'lifeItem', 'id', li.id::text)
                order by li.created_at, li.id
              )
       from public.field_life_items li
       where li.journey_id = p_journey
         and li.visibility = 'shared'),
      '[]'::jsonb
    )
  into v_refs;

  update public.field_journeys
  set subject_references = coalesce(v_refs, '[]'::jsonb)
  where id = p_journey;
end;
$$;

revoke all on function private.refresh_journey_subjects(uuid)
  from public, anon, authenticated;

-- Accumulation is driven by triggers rather than by a call at the end of
-- `confirm_shared_direction`.
--
-- Two reasons. It keeps this migration from re-declaring that whole function to
-- add one line, and — the reason that matters — it makes the accumulation
-- ongoing rather than confirm-time only. Evidence attached to a journey months
-- later, an action completed, a life item made private: each updates provenance
-- at the moment it happens, which is what "subjects accumulate over the
-- journey's life" has to mean to be true.

create or replace function private.journey_subjects_touch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old uuid := null;
  v_new uuid := null;
begin
  if tg_op <> 'INSERT' then v_old := old.journey_id; end if;
  if tg_op <> 'DELETE' then v_new := new.journey_id; end if;

  if v_new is not null then
    perform private.refresh_journey_subjects(v_new);
  end if;
  -- A row moved off a journey, or was deleted from one, must also stop being
  -- named as its provenance.
  if v_old is not null and v_old is distinct from v_new then
    perform private.refresh_journey_subjects(v_old);
  end if;

  return null;
end;
$$;

revoke all on function private.journey_subjects_touch()
  from public, anon, authenticated;

drop trigger if exists journey_subjects_from_life_items
  on public.field_life_items;
create trigger journey_subjects_from_life_items
  after insert or update or delete on public.field_life_items
  for each row execute function private.journey_subjects_touch();

drop trigger if exists journey_subjects_from_evidence
  on public.field_evidence;
create trigger journey_subjects_from_evidence
  after insert or update or delete on public.field_evidence
  for each row execute function private.journey_subjects_touch();

commit;
