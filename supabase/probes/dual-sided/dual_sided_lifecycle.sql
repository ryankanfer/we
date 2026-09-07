-- Dual-sided lifecycle run.
--
-- Two authenticated sessions, A and B, driven through the full relationship
-- lifecycle: sign-up, pairing, hue, private reflection, reveal request,
-- private answering, mutual reveal, decline, withdrawal, resolution, shared
-- Life and Ahead work, presence and signal consent, archive, and relationship
-- end. Every step asserts what each side can and cannot see.
--
-- Run it with supabase/probes/dual-sided/run_dual_sided.sh.

\set ON_ERROR_STOP on
\pset pager off
set client_min_messages = warning;

drop schema if exists wetest cascade;
create schema wetest;

create table wetest.results (
  id serial primary key,
  phase text not null,
  name text not null,
  passed boolean not null,
  detail text
);

create table wetest.ctx (key text primary key, value text not null);

create function wetest.put(p_key text, p_value text)
returns void language sql security definer as $$
  insert into wetest.ctx values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
$$;

create function wetest.get(p_key text)
returns text language sql security definer stable as $$
  select value from wetest.ctx where key = p_key;
$$;

create function wetest.uid(p_key text)
returns uuid language sql security definer stable as $$
  select value::uuid from wetest.ctx where key = p_key;
$$;

create function wetest.ok(p_condition boolean, p_name text, p_detail text default null)
returns void language plpgsql security definer as $$
begin
  insert into wetest.results (phase, name, passed, detail)
  values (coalesce(current_setting('wetest.phase', true), 'general'),
          p_name, coalesce(p_condition, false), p_detail);
end;
$$;

-- Asserts that a statement is refused. A trust boundary that fails open is the
-- whole product failing, so "it raised" is itself the assertion.
create function wetest.rejects(p_sql text, p_name text)
returns void language plpgsql security invoker as $$
begin
  execute p_sql;
  perform wetest.ok(false, p_name, 'statement was allowed but should have been refused');
exception when others then
  perform wetest.ok(true, p_name, 'refused: ' || sqlerrm);
end;
$$;

create function wetest.phase(p_name text)
returns void language sql security definer as $$
  select set_config('wetest.phase', p_name, false);
$$;

-- Signing in is exactly what PostgREST does for a real session: set the JWT
-- claims, act as the authenticated role.
create function wetest.signin(p_key text)
returns void language plpgsql security definer as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', wetest.get(p_key), 'role', 'authenticated')::text,
    false
  );
end;
$$;

create function wetest.signout()
returns void language plpgsql security definer as $$
begin
  perform set_config('request.jwt.claims', '', false);
end;
$$;

grant usage on schema wetest to authenticated;
grant execute on all functions in schema wetest to authenticated;


-- =====================================================================
select wetest.phase('01 sign-up');
-- =====================================================================
-- Supabase Auth owns this insert; the app never writes auth.users itself.
insert into auth.users (email, raw_user_meta_data)
values ('a@we.test', '{"name":"Avery"}'), ('b@we.test', '{"name":"Blair"}');

select wetest.put('a', (select id::text from auth.users where email = 'a@we.test'));
select wetest.put('b', (select id::text from auth.users where email = 'b@we.test'));

select wetest.ok(
  (select count(*) = 2 from public.profiles
   where id in (wetest.uid('a'), wetest.uid('b'))),
  'both sign-ups create a profile'
);
select wetest.ok(
  (select name = 'Avery' from public.profiles where id = wetest.uid('a')),
  'profile carries the name from sign-up metadata'
);


-- =====================================================================
select wetest.phase('02 pairing');
-- =====================================================================
set role authenticated;
select wetest.signin('a');
select wetest.put('code', (select (public.create_couple() ->> 'join_code')));
select wetest.put('couple', (select public.my_couple_id()::text));

select wetest.ok(wetest.get('code') is not null, 'A creating a WE space returns a join code');
select wetest.ok(
  (select count(*) = 1 from public.couple_members where couple_id = wetest.uid('couple')),
  'the space starts with one member'
);

-- A cannot join the space they already belong to.
select wetest.rejects(
  format('select public.join_couple(%L)', wetest.get('code')),
  'A cannot join their own space twice'
);

select wetest.signin('b');
select wetest.rejects(
  'select public.join_couple(''ZZZZZZ'')',
  'a wrong join code is refused'
);
select public.join_couple(wetest.get('code'));

select wetest.ok(
  (select public.my_couple_id() = wetest.uid('couple')),
  'B lands in the same WE space'
);
select wetest.ok(
  (select array_agg(hue order by hue) = array['burgundy','sage']
   from public.couple_members where couple_id = wetest.uid('couple')),
  'the two sides hold distinct hues'
);
select wetest.ok(
  (select count(*) = 2 from public.profiles),
  'each side can read both names once paired'
);

select wetest.ok(
  (select count(*) > 0 from public.insights where couple_id = wetest.uid('couple')),
  'pairing seeds the shared field with insights'
);


-- =====================================================================
select wetest.phase('03 private reflection');
-- =====================================================================
select wetest.signin('a');
insert into public.reflections (couple_id, owner_id, domain, kind, text)
values (wetest.uid('couple'), wetest.uid('a'), 'us', 'reflection',
        'A private note that must never cross.');
select wetest.ok(
  (select count(*) = 1 from public.reflections),
  'A can read A''s own reflection'
);

select wetest.signin('b');
select wetest.ok(
  (select count(*) = 0 from public.reflections),
  'B cannot read A''s reflection'
);
select wetest.rejects(
  format(
    'insert into public.reflections (couple_id, owner_id, domain, kind, text) '
    || 'values (%L, %L, ''us'', ''reflection'', ''forged'')',
    wetest.get('couple'), wetest.get('a')
  ),
  'B cannot write a reflection in A''s name'
);


-- =====================================================================
select wetest.phase('04 reveal request');
-- =====================================================================
select wetest.signin('a');
select wetest.put('i1', (
  select i.id::text from public.insights i
  join public.insight_consent ic on ic.insight_id = i.id
  where i.couple_id = wetest.uid('couple') and ic.readiness = 'idle'
  order by i.sort limit 1
));
select public.request_reveal(wetest.uid('i1'));

select wetest.signin('b');
select wetest.ok(
  (select readiness = 'requested' and initiator_id = wetest.uid('a')
   from public.insight_consent where insight_id = wetest.uid('i1')),
  'B sees the topic and who asked'
);
select wetest.ok(
  (select count(*) = 0 from public.responses where insight_id = wetest.uid('i1')),
  'a request exposes no answer'
);

-- Answering before both sides open it together is refused on both sides.
select wetest.rejects(
  format('select public.submit_response(%L, ''Yes'')', wetest.get('i1')),
  'B cannot answer before the item is opened together'
);
select public.accept_reveal(wetest.uid('i1'));
select wetest.ok(
  (select readiness = 'accepted' and visibility = 'mutual'
   from public.insight_consent where insight_id = wetest.uid('i1')),
  'B accepting opens the item together'
);

select wetest.signin('a');
select wetest.rejects(
  format('select public.accept_reveal(%L)', wetest.get('i1')),
  'A cannot accept A''s own request'
);


-- =====================================================================
select wetest.phase('05 private answers, mutual reveal');
-- =====================================================================
select wetest.signin('a');
select wetest.put('opt', (select options[1] from public.insights where id = wetest.uid('i1')));
select wetest.put('opt2', (select options[array_upper(options,1)] from public.insights where id = wetest.uid('i1')));
select public.submit_response(wetest.uid('i1'), wetest.get('opt'), 'A''s reasoning');

select wetest.ok(
  (select count(*) = 1 from public.responses
   where insight_id = wetest.uid('i1') and profile_id = wetest.uid('a')),
  'A sees A''s own submitted answer'
);

select wetest.signin('b');
select wetest.ok(
  (select count(*) = 0 from public.responses
   where insight_id = wetest.uid('i1') and profile_id = wetest.uid('a')),
  'B cannot read A''s answer before answering'
);
select wetest.ok(
  (select has_answered from public.partner_answer_statuses()
   where insight_id = wetest.uid('i1') and profile_id = wetest.uid('a')),
  'B sees only that A has answered, never what'
);
select wetest.rejects(
  format('select public.submit_response(%L, ''not-an-option'')', wetest.get('i1')),
  'an answer outside the offered options is refused'
);

select public.submit_response(wetest.uid('i1'), wetest.get('opt2'), 'B''s reasoning');
select wetest.ok(
  (select count(*) = 2 from public.responses where insight_id = wetest.uid('i1')
     and status = 'revealed'),
  'both answers reveal at the same moment for B'
);
select wetest.rejects(
  format('select public.submit_response(%L, %L)', wetest.get('i1'), wetest.get('opt')),
  'an answer cannot be changed after it is revealed'
);

select wetest.signin('a');
select wetest.ok(
  (select choice = wetest.get('opt2') from public.responses
   where insight_id = wetest.uid('i1') and profile_id = wetest.uid('b')),
  'A now reads B''s answer'
);


-- =====================================================================
select wetest.phase('06 resolution and archive eligibility');
-- =====================================================================
select public.resolve_insight(wetest.uid('i1'), 'settled', wetest.get('opt2'));
select wetest.ok(
  (select resolution_type = 'settled' from public.insight_consent
   where insight_id = wetest.uid('i1')),
  'a mutual item can be resolved together'
);
select wetest.rejects(
  format('select public.request_reveal(%L)', wetest.get('i1')),
  'a resolved item cannot be reopened by a new request'
);


-- =====================================================================
select wetest.phase('07 decline stays owner-only');
-- =====================================================================
select wetest.signin('a');
select wetest.put('i2', (
  select i.id::text from public.insights i
  join public.insight_consent ic on ic.insight_id = i.id
  where i.couple_id = wetest.uid('couple') and ic.readiness = 'idle'
    and i.id <> wetest.uid('i1')
  order by i.sort limit 1
));
select public.request_reveal(wetest.uid('i2'));

select wetest.signin('b');
select public.decline_reveal(wetest.uid('i2'));
select wetest.ok(
  (select count(*) = 1 from public.insight_declines where insight_id = wetest.uid('i2')),
  'B sees B''s own decline'
);

select wetest.signin('a');
select wetest.ok(
  (select count(*) = 0 from public.insight_declines where insight_id = wetest.uid('i2')),
  'A sees no trace of the decline'
);
select wetest.ok(
  (select readiness = 'requested' from public.insight_consent
   where insight_id = wetest.uid('i2')),
  'A continues to see quiet waiting'
);
select wetest.rejects(
  format('select public.decline_reveal(%L)', wetest.get('i2')),
  'A cannot decline A''s own request'
);


-- =====================================================================
select wetest.phase('08 withdrawal leaves nothing behind');
-- =====================================================================
select public.withdraw_reveal(wetest.uid('i2'));
select wetest.ok(
  (select readiness = 'idle' and initiator_id is null and requested_at is null
   from public.insight_consent where insight_id = wetest.uid('i2')),
  'withdrawing returns the item to rest'
);
select wetest.signin('b');
select wetest.ok(
  (select count(*) = 0 from public.insight_declines where insight_id = wetest.uid('i2')),
  'withdrawal clears the decline record on the partner side too'
);
-- Grace deliberately outlives the invitation: B declined, so the topic rests
-- for B even though A withdrew. A learns nothing from that asymmetry.
select wetest.ok(
  (select suppress_until > now() from public.insight_grace
   where insight_id = wetest.uid('i2') and profile_id = wetest.uid('b')),
  'B keeps grace on a topic B declined'
);
select wetest.ok(
  (select count(*) = 0 from public.insights where id = wetest.uid('i2')),
  'the declined topic rests out of B''s field during grace'
);
select wetest.signin('a');
select wetest.ok(
  (select count(*) = 0 from public.insight_grace),
  'A cannot see that any grace exists'
);
select wetest.ok(
  (select count(*) = 1 from public.insights where id = wetest.uid('i2')),
  'the topic simply sits idle for A, with no explanation offered'
);


-- =====================================================================
select wetest.phase('09 Life: shared responsibility and handoff');
-- =====================================================================
select wetest.signin('a');
select wetest.put('resp', public.create_responsibility(
  wetest.uid('couple'), 'Call the plumber', 'Leak under the sink', wetest.uid('a')
)::text);

select wetest.signin('b');
select wetest.ok(
  (select count(*) = 1 from public.responsibilities where id = wetest.uid('resp')),
  'B sees the responsibility A created'
);

select wetest.signin('a');
select wetest.put('handoff', public.offer_responsibility_handoff(
  wetest.uid('resp'), wetest.uid('b')
)::text);
select wetest.rejects(
  format('select public.respond_responsibility_handoff(%L, true)', wetest.get('handoff')),
  'A cannot accept a handoff A offered'
);

select wetest.signin('b');
select public.respond_responsibility_handoff(wetest.uid('handoff'), true);
select wetest.ok(
  (select owner_id = wetest.uid('b') from public.responsibilities where id = wetest.uid('resp')),
  'accepting a handoff moves ownership'
);


-- =====================================================================
select wetest.phase('10 Ahead: a plan both sides can shape');
-- =====================================================================
select wetest.put('plan', public.create_plan(
  wetest.uid('couple'), 'Friday dinner', 'Somewhere quiet', current_date + 3
)::text);
select public.set_plan_approach(wetest.uid('plan'), 'together', 'I want this one');

select wetest.signin('a');
select wetest.ok(
  (select count(*) = 1 from public.plans where id = wetest.uid('plan')),
  'A sees the plan B created'
);
select wetest.ok(
  (select count(*) = 0 from public.plan_approaches where plan_id = wetest.uid('plan')),
  'A cannot read B''s approach before A has one of their own'
);
select public.set_plan_approach(wetest.uid('plan'), 'gently', 'Let''s keep it easy');
select wetest.ok(
  (select count(*) = 2 from public.plan_approaches
   where plan_id = wetest.uid('plan') and revealed_at is not null),
  'both approaches reveal at the same moment'
);
select wetest.ok(
  (select approach = 'together' from public.plan_approaches
   where plan_id = wetest.uid('plan') and profile_id = wetest.uid('b')),
  'A now reads B''s approach'
);
select public.set_plan_status(wetest.uid('plan'), 'completed');
select wetest.ok(
  (select status = 'completed' from public.plans where id = wetest.uid('plan')),
  'either side can complete a shared plan'
);


-- =====================================================================
select wetest.phase('11 presence and signal consent stay private');
-- =====================================================================
select public.set_relationship_presence('together');
select public.set_signal_consent('weekly_rhythm', true);
select wetest.ok(
  (select count(*) = 4 from public.signal_consents where profile_id = wetest.uid('a')),
  'A reads A''s own four signal consents'
);
select wetest.ok(
  (select enabled from public.signal_consents
   where profile_id = wetest.uid('a') and signal = 'weekly_rhythm'),
  'A''s signal choice is recorded'
);

select wetest.signin('b');
select wetest.ok(
  (select count(*) = 0 from public.signal_consents where profile_id = wetest.uid('a')),
  'B cannot read A''s signal consent'
);
select wetest.ok(
  (select count(*) >= 1 from public.relationship_presence where couple_id = wetest.uid('couple')),
  'presence is shared by design'
);


-- =====================================================================
select wetest.phase('12 outsider is refused');
-- =====================================================================
reset role;
insert into auth.users (email, raw_user_meta_data)
values ('c@we.test', '{"name":"Casey"}');
select wetest.put('c', (select id::text from auth.users where email = 'c@we.test'));
set role authenticated;
select wetest.signin('c');
select wetest.ok(
  (select count(*) = 0 from public.insights),
  'an outsider reads no insights'
);
select wetest.ok(
  (select count(*) = 0 from public.plans) and (select count(*) = 0 from public.responsibilities),
  'an outsider reads no Life or Ahead rows'
);
select wetest.rejects(
  format('select public.request_reveal(%L)', wetest.get('i2')),
  'an outsider cannot touch consent state'
);
select wetest.rejects(
  format('select public.create_plan(%L, ''intrusion'')', wetest.get('couple')),
  'an outsider cannot write into the space'
);


-- =====================================================================
select wetest.phase('13 relationship end and archive');
-- =====================================================================
select wetest.signin('b');
select public.delete_my_account();

select wetest.signin('a');
select wetest.ok(
  (select count(*) = 1 from public.relationship_archives where owner_id = wetest.uid('a')),
  'the remaining side keeps a sanitized archive'
);
select wetest.ok(
  (select jsonb_array_length(snapshot -> 'resolutions') = 1
   from public.relationship_archives where owner_id = wetest.uid('a')),
  'the archive carries the resolved item'
);
select wetest.ok(
  (select snapshot::text not like '%private note%'
   from public.relationship_archives where owner_id = wetest.uid('a')),
  'the archive carries no private reflection'
);
select wetest.ok(
  (select snapshot::text not like '%reasoning%'
   from public.relationship_archives where owner_id = wetest.uid('a')),
  'the archive carries no answer text'
);
select wetest.ok(
  (select count(*) = 0 from public.insights),
  'the live shared field is gone once the relationship ends'
);
select wetest.ok(
  (select public.my_couple_id() is null),
  'A is no longer in a WE space'
);

select wetest.signin('b');
select wetest.ok(
  (select count(*) = 0 from public.relationship_archives),
  'the departed side keeps no archive'
);
select wetest.ok(
  (select count(*) = 0 from public.profiles where id = wetest.uid('b')),
  'the departed profile is gone'
);

reset role;
select wetest.signout();
