begin;
create extension if not exists pgtap with schema extensions;
select plan(13);
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('96000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','intelligence-a@example.com','x','{}','{"name":"A"}',now(),now()),
('96000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','intelligence-b@example.com','x','{}','{"name":"B"}',now(),now());
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"96000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select lives_ok($$select public.intake_write('96100000-0000-0000-0000-000000000001','96200000-0000-0000-0000-000000000001',0,'{"id":"96100000-0000-0000-0000-000000000001","resources":[]}','{"title":"Dinner"}')$$,'private capture works without a couple');
select is((select count(*)::int from public.private_artifacts),1,'owner can retrieve original');
select is((public.intake_write('96100000-0000-0000-0000-000000000001','96200000-0000-0000-0000-000000000001',0,'{"id":"96100000-0000-0000-0000-000000000001","resources":[]}','{"title":"Dinner"}')->>'version')::int,1,'lost acknowledgment retries the same version');
select is((select count(*)::int from public.private_artifacts),1,'retry did not duplicate');
select ok(public.intake_write('96100000-0000-0000-0000-000000000001','96200000-0000-0000-0000-000000000002',0,'{"id":"96100000-0000-0000-0000-000000000001","resources":[]}','{"title":"Stale edit"}') ? 'conflict','stale edit returns recoverable conflict');
select is((select content->>'title' from public.private_artifacts),'Dinner','stale edit cannot replace newer work');
select set_config('request.jwt.claims','{"sub":"96000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select count(*)::int from public.private_artifacts),0,'other account cannot retrieve originals');
select set_config('request.jwt.claims','{"sub":"96000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select lives_ok($$select public.intake_delete_everywhere('96100000-0000-0000-0000-000000000001')$$,'delete everywhere is owner authorized without pairing');
select is((select count(*)::int from public.private_artifacts),0,'deletion removes the content');
select throws_ok($$select public.intake_write('96100000-0000-0000-0000-000000000001','96200000-0000-0000-0000-000000000003',0,'{"id":"96100000-0000-0000-0000-000000000001","resources":[]}','{"title":"Resurrect"}')$$,'P0001','artifact deleted','offline writes cannot resurrect deletion');
reset role;
select throws_ok($$select public.intake_record_verification('96000000-0000-0000-0000-000000000001','private-originals','96000000-0000-0000-0000-000000000001/96100000-0000-0000-0000-000000000001/'||repeat('a',64),repeat('a',64),20)$$,'P0001','artifact deleted','late verification cannot recreate processing history');
select throws_ok($$insert into storage.objects(bucket_id,name) values('private-originals','96000000-0000-0000-0000-000000000001/96100000-0000-0000-0000-000000000001/'||repeat('a',64))$$,'P0001','artifact deleted','late storage inserts cannot outlive cleanup');
select is((select count(*)::int from public.intake_cleanup_jobs('96000000-0000-0000-0000-000000000001','96100000-0000-0000-0000-000000000001')),1,'cleanup can target the requested object without a page-limit false acknowledgment');
select * from finish();
rollback;
