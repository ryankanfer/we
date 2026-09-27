// npm install --prefix /tmp/we-sql-check @electric-sql/pglite
// NODE_PATH=/tmp/we-sql-check/node_modules node scripts/intelligence/check-sql.mjs
import {createRequire} from 'node:module';
const require = createRequire(import.meta.url);
const {PGlite} = require('@electric-sql/pglite');
const {pgcrypto} = require('@electric-sql/pglite/contrib/pgcrypto');
import fs from 'node:fs';
const root=new URL('../../',import.meta.url).pathname;
const db=new PGlite({extensions:{pgcrypto}});
try {
await db.exec(fs.readFileSync(root+'/supabase/probes/dual-sided/supabase_shim.sql','utf8'));
await db.exec(`
 alter default privileges in schema public grant all on tables to anon,authenticated,service_role;
 alter table auth.users add column instance_id uuid,add column aud text,add column role text,add column encrypted_password text,add column email_confirmed_at timestamptz,add column raw_app_meta_data jsonb,add column updated_at timestamptz,add column is_anonymous boolean default false;
 create schema storage; create schema vault;
 create table vault.secrets(name text); create table vault.decrypted_secrets(name text,decrypted_secret text);
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,metadata jsonb,user_metadata jsonb,owner uuid,created_at timestamptz default now(),updated_at timestamptz default now());
 alter table storage.objects enable row level security;
 grant usage on schema storage to authenticated,service_role;
 grant all on storage.objects,storage.buckets to authenticated,service_role;
 create function storage.foldername(text) returns text[] language sql immutable as $$ select (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1] $$;
 create function storage.filename(text) returns text language sql immutable as $$ select (string_to_array($1,'/'))[array_length(string_to_array($1,'/'),1)] $$;
`);
for (const name of fs.readdirSync(root+'/supabase/migrations').filter(x=>x.endsWith('.sql')).sort()) {
 try {await db.exec(fs.readFileSync(root+'/supabase/migrations/'+name,'utf8'));}
 catch(error) {console.error('MIGRATION',name,error.message,error.where);process.exit(1);}
}
console.log('All repository migrations applied to isolated PostgreSQL with platform shims.');
await db.exec(`
 create function public.plan(integer) returns text language sql as $$select 'plan '||$1$$;
 create function public.ok(boolean,text) returns text language plpgsql as $$begin if $1 is distinct from true then raise exception 'ASSERTION FAILED: %',$2; end if; return 'PASS '||$2; end$$;
 create function public.is(anyelement,anyelement,text) returns text language plpgsql as $$begin if $1 is distinct from $2 then raise exception 'ASSERTION FAILED: % (% vs %)',$3,$1,$2; end if; return 'PASS '||$3; end$$;
 create function public.lives_ok(text,text) returns text language plpgsql as $$begin execute $1; return 'PASS '||$2; end$$;
 create function public.throws_ok(text,text,text,text) returns text language plpgsql as $$declare code text; message text; begin begin execute $1; exception when others then get stacked diagnostics code=returned_sqlstate,message=message_text; if code=$2 and message=$3 then return 'PASS '||$4; else raise exception 'Wrong failure % % expected % %',code,message,$2,$3; end if; end; raise exception 'ASSERTION FAILED expected failure: %',$4; end$$;
 create function public.finish() returns text language sql as $$select 'complete'$$;
`);
let sql=fs.readFileSync(root+'/supabase/tests/native_intelligence.test.sql','utf8').replace('create extension if not exists pgtap with schema extensions;','');
const result=await db.exec(sql);
for(const statement of result)for(const row of statement.rows) for(const value of Object.values(row)) if(typeof value==='string'&&value.startsWith('PASS'))console.log(value);
const publication=await db.exec(fs.readFileSync(root+'/supabase/tests/intelligence_publication.test.sql','utf8').replace('create extension if not exists pgtap with schema extensions;',''));
for(const statement of publication)for(const row of statement.rows)for(const value of Object.values(row))if(typeof value==='string'&&value.startsWith('PASS'))console.log(value);
await db.close();
}catch(error){console.error(error.message,error.where);process.exit(1)}
