-- "Both phones wake at the same instant." The server half of it.
--
-- THE RULE THIS IS BUILT UNDER
--
-- **WE never sends a notification containing news, only ones inviting
-- presence.** Nothing that arrives on a lock screen may carry a name, a
-- decision, a message, a count, or anything derived from private material. The
-- one thing a notification may ever say is that WE is worth opening now, and
-- the app says the rest to a person who is holding it.
--
-- So the payload here is a fixed string, identical for every couple and every
-- arrival, chosen once and asserted from the app's own copy in
-- `WEArrivalNotificationTests`. There is no template and nothing to
-- interpolate into.
--
-- THE CLIENT CANNOT MAKE THE OTHER PHONE SPEAK
--
-- The only thing that enqueues an arrival is a trigger on `couple_members`,
-- firing when the second member row lands — which is to say, after a
-- successful redemption inside `join_couple`. There is no RPC, no grant, and
-- no writable path from any client into `arrival_notifications`, because a
-- client that can cause the other person's phone to make a noise is a client
-- that can be made to do it repeatedly.
--
-- IDEMPOTENT BY A UNIQUENESS CONSTRAINT, NOT BY A CHECK
--
-- `couple_id` is the primary key, so a couple has at most one arrival for as
-- long as the couple exists. A replayed trigger, a re-run migration or a
-- retried worker cannot produce a second one: the constraint refuses it in the
-- database rather than a code path remembering to. If somebody leaves and a
-- new person joins the vacated slot, the row is still there and no second
-- announcement is sent, which is the correct answer — an arrival is announced
-- once per space, and the second one is not the same moment.
--
-- DELIVERY FAILURE IS SILENT, AND SO IS REFUSAL
--
-- Presence plus the aggregate RPC drive the ceremony. A push that never
-- arrives costs a convenience and never correctness, so there is no retry
-- storm, no fallback channel, and no "we tried to notify them" receipt — that
-- would be a report on the other person's timing, which is the one thing this
-- product will not do. A person who refused notifications is in exactly the
-- same product as a person who accepted: the arrival is waiting when they next
-- open it.
--
-- TOKENS ARE PERSONAL
--
-- `device_tokens` is owner only in both directions. A partner must never be
-- able to read the other's, and nothing joins tokens to a couple: the worker
-- resolves a couple to its members with the service role and never through a
-- view any client could reach.

begin;

-- MARK: Tokens --------------------------------------------------------------

create table if not exists public.device_tokens (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  token text not null,
  updated_at timestamptz not null default now(),
  primary key (profile_id, token)
);

alter table public.device_tokens enable row level security;

-- Owner only, and singular. Policies are additive, so a second permissive
-- policy naming the couple would hand a partner every device this person owns.
drop policy if exists device_tokens_select on public.device_tokens;
create policy device_tokens_select on public.device_tokens
  for select using (profile_id = (select auth.uid()));

drop policy if exists device_tokens_delete on public.device_tokens;
create policy device_tokens_delete on public.device_tokens
  for delete using (profile_id = (select auth.uid()));

-- Writes go through the RPC, which is what keeps `profile_id` from being
-- something a client chooses.
revoke insert, update on public.device_tokens from anon, authenticated;
grant select, delete on public.device_tokens to authenticated;

create or replace function public.register_device_token(p_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
begin
  if v_user is null then
    raise exception 'not signed in';
  end if;
  if coalesce(trim(p_token), '') = '' then
    return;
  end if;

  insert into public.device_tokens (profile_id, token)
  values (v_user, trim(p_token))
  on conflict (profile_id, token)
  do update set updated_at = now();
end;
$$;

revoke all on function public.register_device_token(text) from public, anon;
grant execute on function public.register_device_token(text) to authenticated;

-- Signing out and deleting an account both have to take the device with them.
-- A token left behind is a phone that keeps being invited into somebody else's
-- relationship.
create or replace function public.forget_device_tokens()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.device_tokens where profile_id = (select auth.uid());
$$;

revoke all on function public.forget_device_tokens() from public, anon;
grant execute on function public.forget_device_tokens() to authenticated;

-- MARK: The arrival ---------------------------------------------------------

create table if not exists public.arrival_notifications (
  couple_id uuid primary key references public.couples(id) on delete cascade,
  created_at timestamptz not null default now(),
  delivered_at timestamptz
);

-- Enabled with no policies at all. Nothing but the service role reads this,
-- and there is deliberately nothing for a client to see: the row's existence
-- and its timestamps are a record of when two people arrived.
alter table public.arrival_notifications enable row level security;
revoke all on public.arrival_notifications from anon, authenticated;

create or replace function private.enqueue_arrival()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_members integer;
begin
  select count(*) into v_members
  from public.couple_members cm
  where cm.couple_id = new.couple_id;

  if v_members < 2 then
    return new;
  end if;

  insert into public.arrival_notifications (couple_id)
  values (new.couple_id)
  on conflict (couple_id) do nothing;

  return new;
end;
$$;

drop trigger if exists couple_members_arrival on public.couple_members;
create trigger couple_members_arrival
  after insert on public.couple_members
  for each row execute function private.enqueue_arrival();

-- MARK: The worker ----------------------------------------------------------
--
-- Scheduled the same way as the synthesis worker, and with one deliberate
-- difference: a project without the secrets gets a notice rather than a failed
-- migration. The synthesis worker raises, because a deployment that cannot
-- synthesise leaves every answer held forever and reports success. This one
-- cannot leave anything held. The ceremony is correct with push absent
-- entirely, which is why push was built last.

do $$
declare
  v_ready boolean;
begin
  select
    exists (select 1 from pg_available_extensions where name = 'pg_cron')
    and exists (select 1 from pg_available_extensions where name = 'pg_net')
    and exists (select 1 from pg_available_extensions where name = 'supabase_vault')
  into v_ready;

  if not v_ready then
    raise notice
      'pg_cron/pg_net/supabase_vault unavailable; arrivals will not be announced';
    return;
  end if;

  create extension if not exists pg_cron with schema extensions;
  create extension if not exists pg_net with schema extensions;

  -- Created out of band, once per project:
  --
  --   select vault.create_secret('<dedicated sb_secret_ key>', 'arrival_worker_key');
  --   select vault.create_secret('https://<ref>.supabase.co', 'arrival_worker_url');
  if (
    select count(distinct name)
    from vault.decrypted_secrets
    where name in ('arrival_worker_key', 'arrival_worker_url')
  ) <> 2 then
    raise notice
      'vault secrets arrival_worker_key/arrival_worker_url are missing; arrivals will not be announced';
    return;
  end if;

  perform cron.unschedule(jobid)
  from cron.job where jobname = 'we-announce-arrival';

  perform cron.schedule(
    'we-announce-arrival',
    '* * * * *',
    $job$
    select net.http_post(
      url := (
        select decrypted_secret || '/functions/v1/announce-arrival'
        from vault.decrypted_secrets where name = 'arrival_worker_url'
      ),
      headers := jsonb_build_object(
        'content-type', 'application/json',
        'apikey', (
          select decrypted_secret
          from vault.decrypted_secrets where name = 'arrival_worker_key'
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
