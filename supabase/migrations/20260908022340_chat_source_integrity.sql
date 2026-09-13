alter table public.field_chat_messages add constraint chat_couple_message unique(couple_id,id);
alter table public.field_chat_messages add constraint chat_source_same_couple foreign key(couple_id,source_id) references public.field_chat_messages(couple_id,id) on delete set null(source_id);
drop policy chat_send on public.field_chat_messages;
create policy chat_send on public.field_chat_messages for insert to authenticated with check(
 couple_id=(select public.my_couple_id()) and sender_id=(select auth.uid()) and confirmed_by is null
 and created_at between now()-interval '5 minutes' and now()+interval '5 minutes'
 and (context_id is null or (context_kind='goal' and exists(select 1 from public.field_horizons h where h.id=context_id and h.couple_id=field_chat_messages.couple_id))
 or (context_kind='life' and exists(select 1 from public.field_life_items i where i.id=context_id and i.couple_id=field_chat_messages.couple_id and coalesce(i.visibility,'shared')='shared')))
);
