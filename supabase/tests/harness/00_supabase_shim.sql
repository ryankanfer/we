-- Test harness: the Supabase-managed objects the WE migrations build on.
--
-- On a real project these are created by the platform (GoTrue, Realtime, the
-- default role grants), not by our migrations, so a plain Postgres has to be
-- given them before `supabase/migrations` will apply. This file exists so the
-- pgTAP suites can run in CI against a stock `postgres` service container
-- without Docker-in-Docker.
--
-- It is a stand-in, not a mirror. It reproduces the parts the suites depend on:
-- the anon/authenticated/service_role roles, `auth.users`, `auth.uid()`, the
-- `supabase_realtime` publication, the `extensions` schema, and Supabase's
-- default privilege grants on `public` — that last one matters, because it is
-- exactly what makes the grant-hardening assertions meaningful.
--
-- Run against a scratch database only. Never against a real project.

-- Roles are cluster-wide, so a second scratch database on the same server must
-- not trip over them.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end;
$$;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to anon, authenticated, service_role, public;

-- Supabase puts `extensions` on the search path, so migrations and tests can
-- call pgcrypto and pgTAP unqualified. Match that for whatever scratch database
-- this harness was pointed at.
do $$
begin
  execute format(
    'alter database %I set search_path = public, extensions',
    current_database()
  );
end;
$$;

create schema auth;
grant usage on schema auth to anon, authenticated, service_role;

-- The columns the suites insert, in the shape GoTrue creates them.
create table auth.users (
  instance_id uuid,
  id uuid primary key default gen_random_uuid(),
  aud varchar(255),
  role varchar(255),
  email text,
  encrypted_password varchar(255),
  email_confirmed_at timestamptz,
  raw_app_meta_data jsonb default '{}'::jsonb,
  raw_user_meta_data jsonb default '{}'::jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(
    coalesce(
      current_setting('request.jwt.claim.sub', true),
      (current_setting('request.jwt.claims', true)::jsonb ->> 'sub')
    ),
    ''
  )::uuid
$$;

create or replace function auth.role()
returns text
language sql
stable
as $$
  select coalesce(
    current_setting('request.jwt.claim.role', true),
    (current_setting('request.jwt.claims', true)::jsonb ->> 'role')
  )
$$;

grant execute on function auth.uid() to anon, authenticated, service_role, public;
grant execute on function auth.role() to anon, authenticated, service_role, public;

create publication supabase_realtime;

-- Supabase grants these by default on `public`. Keeping them here is the point:
-- our migrations have to revoke what they do not want, and the suites assert it.
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on sequences to anon, authenticated, service_role;
