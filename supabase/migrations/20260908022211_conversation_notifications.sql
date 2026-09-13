alter table public.field_chat_preferences add column notifications boolean not null default true;
drop function public.field_chat_preference(boolean,boolean);
create function public.field_chat_preference(p_notices boolean,p_read boolean default false,p_notifications boolean default null)
returns void language sql security invoker set search_path='' as $$
 insert into public.field_chat_preferences(couple_id,profile_id,notices,read_at,notifications)
 values(public.my_couple_id(),auth.uid(),coalesce(p_notices,false),case when p_read then now() else null end,coalesce(p_notifications,true))
 on conflict(couple_id,profile_id) do update set notices=coalesce(p_notices,field_chat_preferences.notices),read_at=coalesce(excluded.read_at,field_chat_preferences.read_at),notifications=coalesce(p_notifications,field_chat_preferences.notifications);
$$;
revoke all on function public.field_chat_preference(boolean,boolean,boolean) from public,anon;
grant execute on function public.field_chat_preference(boolean,boolean,boolean) to authenticated;
create table public.field_chat_notifications (
 couple_id uuid not null,
 profile_id uuid not null,
 last_message_at timestamptz not null,
 delivered_at timestamptz,
 primary key(couple_id,profile_id),
 foreign key(couple_id,profile_id) references public.couple_members(couple_id,profile_id) on delete cascade
);
alter table public.field_chat_notifications enable row level security;
revoke all on public.field_chat_notifications from public,anon,authenticated;
grant all on public.field_chat_notifications to service_role;
create function private.queue_chat_notification() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is distinct from new.sender_id then return new; end if;
 insert into public.field_chat_notifications(couple_id,profile_id,last_message_at)
 select new.couple_id,m.profile_id,new.created_at from public.couple_members m where m.couple_id=new.couple_id and m.profile_id<>new.sender_id
 on conflict(couple_id,profile_id) do update set last_message_at=excluded.last_message_at;
 return new;
end $$;
revoke all on function private.queue_chat_notification() from public,anon,authenticated;
create trigger queue_chat_notification after insert on public.field_chat_messages for each row execute function private.queue_chat_notification();
-- Reuse the established dedicated worker references; never embed credentials.
do $$ begin
 if (select count(distinct name) from vault.secrets where name in ('arrival_worker_key','arrival_worker_url'))=2 then
 perform cron.schedule('we-notify-conversation','* * * * *',$job$
 select net.http_post(url := (select decrypted_secret || '/functions/v1/notify-conversation' from vault.decrypted_secrets where name='arrival_worker_url'),headers := jsonb_build_object('content-type','application/json','apikey',(select decrypted_secret from vault.decrypted_secrets where name='arrival_worker_key')),body := '{}'::jsonb,timeout_milliseconds := 20000);
 $job$);
 end if;
end $$;
