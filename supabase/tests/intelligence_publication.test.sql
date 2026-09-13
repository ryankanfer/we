begin;
create extension if not exists pgtap with schema extensions;
select plan(10);
insert into auth.users(id,email,raw_user_meta_data) values
('97000000-0000-0000-0000-000000000001','pub-a@example.com','{"name":"A"}'),
('97000000-0000-0000-0000-000000000002','pub-b@example.com','{"name":"B"}');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"97000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.create_couple();
reset role;
insert into public.couple_members(couple_id,profile_id,hue,member_slot) select couple_id,'97000000-0000-0000-0000-000000000002','sage',2 from public.couple_members where profile_id='97000000-0000-0000-0000-000000000001';
set local role authenticated;
select public.intake_create_publication('97100000-0000-0000-0000-000000000001','97200000-0000-0000-0000-000000000001',1,'Dinner','Friday','food','[]','[]',jsonb_build_object('audience',public.my_couple_id(),'expectedPublishedRevision',0,'expectedLifeVersion',0,'timing',jsonb_build_object('precision','day','startDay','2026-09-18')));
select lives_ok($$select public.intake_finalize_publication('97100000-0000-0000-0000-000000000001')$$,'reviewed publication finalizes');
select is((select intelligence_version::int from public.field_life_items where title='Dinner'),1,'publication is versioned');
select is((select due_on::text from public.field_life_items where title='Dinner'),'2026-09-18','accepted timing reaches Life');
select throws_ok($$update public.field_life_items set title='stale direct write' where title='Dinner'$$,'P0001','use versioned item update','legacy direct writes cannot bypass version checks');
select public.intake_create_publication('97100000-0000-0000-0000-000000000002','97200000-0000-0000-0000-000000000001',2,'Dinner corrected','Friday','food','[]','[]',jsonb_build_object('audience',public.my_couple_id(),'expectedPublishedRevision',1,'expectedLifeVersion',1));
select lives_ok($$select public.intake_finalize_publication('97100000-0000-0000-0000-000000000002')$$,'reviewed correction finalizes');
select is((select count(*)::int from public.field_life_items where title like 'Dinner%'),1,'corrected publication is one canonical object');
select is((select intelligence_version::int from public.field_life_items where title='Dinner corrected'),2,'correction advances shared version');
select is((select count(distinct life_item_id)::int from public.share_publication_sessions where draft_id='97200000-0000-0000-0000-000000000001'),1,'both reviewed revisions point to canonical item');
select lives_ok($$select public.intake_delete_everywhere('97200000-0000-0000-0000-000000000001')$$,'published artifact can be deleted everywhere');
select is((select count(*)::int from public.field_life_items where title like 'Dinner%'),0,'both viewers lose published copy');
select * from finish();
rollback;
