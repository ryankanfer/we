begin;

-- Nothing invoked the synthesis worker.
--
-- `journey_synthesis_jobs` was written on every second submission, the sweep
-- recovered lost claims, and the function README said to POST it every minute
-- — but no migration, script, or workflow ever did. Every job sat queued
-- forever and Us stayed permanently in `.held` ("Your answer is here"), which
-- is indistinguishable from a couple who simply had nothing to resolve yet.
--
-- The credential lives in Vault rather than in a database setting or the job
-- body. `cron.job` rows are readable by anyone who can reach the `cron` schema,
-- and a service-role key inlined into a scheduled command is a key in a table
-- that gets dumped, replicated, and backed up. `vault.decrypted_secrets` is
-- readable only by the roles granted it, and the job reads it at run time.
--
-- Recorded in `docs/PRIVATE_TO_SHARED_CONTRACT.md` under transit and retention:
-- this is a credential at rest in the database, and it is a deliberate choice.

do $$
declare
  v_has_cron boolean;
  v_has_net boolean;
  v_has_vault boolean;
  v_hosted text;
  v_secrets int;
begin
  select exists (select 1 from pg_available_extensions where name = 'pg_cron')
    into v_has_cron;
  select exists (select 1 from pg_available_extensions where name = 'pg_net')
    into v_has_net;
  select exists (select 1 from pg_available_extensions where name = 'supabase_vault')
    into v_has_vault;

  if not (v_has_cron and v_has_net and v_has_vault) then
    -- Local `supabase start` does not carry all three. The feature still works
    -- there when the worker is driven by hand, and this must not fail the
    -- migration lane on a developer machine or in the PR contract job.
    raise notice
      'pg_cron/pg_net/supabase_vault unavailable; the synthesis worker must be scheduled externally';
    return;
  end if;

  create extension if not exists pg_cron with schema extensions;
  create extension if not exists pg_net with schema extensions;

  -- Secrets are created out of band, once per project:
  --
  --   select vault.create_secret('<dedicated sb_secret_ key>', 'synthesis_worker_key');
  --   select vault.create_secret('https://<ref>.supabase.co', 'synthesis_worker_url');
  --
  -- Whether this deployment is expected to carry them is declared out of band
  -- too, once per project:
  --
  --   alter database postgres set we.deployment_is_hosted = 'true';
  --
  -- The extension check above was doing this job and cannot: the CI image
  -- carries all three extensions, so a lane with no Vault secrets fell through
  -- to the exception below and failed schema creation for every branch. Schema
  -- creation and worker scheduling are separate concerns, and only the second
  -- one needs a credential.
  select count(distinct name) into v_secrets
  from vault.decrypted_secrets
  where name in ('synthesis_worker_key', 'synthesis_worker_url');

  v_hosted := coalesce(nullif(current_setting('we.deployment_is_hosted', true), ''), 'unknown');

  if v_hosted = 'false' then
    raise notice
      'we.deployment_is_hosted is false; schema created, synthesis worker not scheduled';
    return;
  end if;

  -- A hosted deployment without either secret is incomplete. Fail the
  -- migration instead of reporting success while leaving every answer held.
  if v_hosted = 'true' and v_secrets <> 2 then
    raise exception
      'vault secrets synthesis_worker_key/synthesis_worker_url are missing; worker not scheduled';
  end if;

  -- Undeclared. Schedule when the credential is there, and say so plainly when
  -- it is not, rather than guessing that an unlabelled database is production.
  --
  -- This branch is the one that trades safety for a working lane: an unflagged
  -- database missing its secrets gets a notice, not the exception. That is the
  -- whole point on CI, and it is a real hole on a hosted project that never set
  -- the flag. Set `we.deployment_is_hosted` on every hosted project so that
  -- deployment takes the `true` branch and keeps the loud failure.
  if v_hosted = 'unknown' and v_secrets <> 2 then
    raise notice
      'we.deployment_is_hosted is unset and no synthesis worker secrets are present; not scheduled';
    return;
  end if;

  if not exists (
    select 1 from vault.decrypted_secrets
    where name = 'synthesis_worker_key'
      and decrypted_secret like 'sb_secret_%'
  ) then
    raise exception
      'synthesis_worker_key must be a dedicated modern sb_secret_ API key';
  end if;

  perform cron.unschedule(jobid)
  from cron.job where jobname = 'we-synthesize-shared-journeys';

  perform cron.schedule(
    'we-synthesize-shared-journeys',
    '* * * * *',
    $job$
    select net.http_post(
      url := (
        select decrypted_secret || '/functions/v1/synthesize-shared-journeys'
        from vault.decrypted_secrets where name = 'synthesis_worker_url'
      ),
      headers := jsonb_build_object(
        'content-type', 'application/json',
        'apikey', (
          select decrypted_secret
          from vault.decrypted_secrets where name = 'synthesis_worker_key'
        )
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 20000
    );
    $job$
  );
end;
$$;

commit;
