begin;

-- A lifecycle announcement outlived the RPC that made it.
--
-- `private.yours_stamp_entry()` neutralises a client's writes to `state`,
-- `ready_at`, `renewal_count`, `presented_at`, `decide_by`, `held_at` and
-- `snoozed_at`, and refuses an edit to a held entry, unless
-- `we.yours_lifecycle` is announced. Every lifecycle RPC announces it with
-- `set_config(..., true)` — which is transaction-local, not function-local,
-- and nothing ever set it back. So once any one of them had run, the guard
-- was open for the rest of the transaction and a direct write could set its
-- own `state` to 'held' or buy itself ten more years of `ready_at`.
--
-- PostgREST gives each request its own transaction, so a client cannot chain
-- an RPC and a table write today. This closes the hole rather than resting on
-- that. Asserted by yours_personal_space.test.sql tests 10, 11, 27 and 29 —
-- four assertions that had never executed, because the schema lane died at
-- 20260820161957 long before pgTAP.

create or replace function private.yours_stamp_entry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- Two conditions, not one. `set_config(..., true)` is transaction-local,
  -- not function-local, so the flag an RPC announces is still standing after
  -- that RPC returns — every later write in the same transaction inherited
  -- the lifecycle door. A client never holds the owner role, and a
  -- `security definer` RPC always does, so the role is what separates them.
  v_lifecycle boolean :=
    nullif(current_setting('we.yours_lifecycle', true), '') = 'on'
    and (select current_user) not in ('anon', 'authenticated');
begin
  if tg_op = 'INSERT' then
    new.owner_id := coalesce(new.owner_id, (select auth.uid()));
    new.created_at := now();
    new.updated_at := now();
    new.renewal_count := 0;
    new.state := 'living';
    new.presented_at := null;
    new.decide_by := null;
    new.snoozed_at := null;
    new.held_at := null;
    new.ready_at := now() + private.yours_interval(0);
  else
    -- Identity is not editable. A row rewritten over somebody else's would be
    -- the one way private writing could change hands.
    new.id := old.id;
    new.owner_id := old.owner_id;
    new.client_id := old.client_id;
    new.created_at := old.created_at;
    new.updated_at := now();

    if not v_lifecycle then
      -- Locked #8, against the client. The RPCs manage this column
      -- themselves: `yours_snooze` refuses a second one, and
      -- `yours_let_this_return` clears it because a fresh first life is
      -- entitled to its own week.
      new.snoozed_at := old.snoozed_at;

      -- An edit. §4: held status must not silently transfer to newly written
      -- material — new words do not inherit permanence — so editing something
      -- held forces an explicit choice, which is an RPC, not this path.
      -- One literal, on one line, deliberately: plpgsql parses RAISE itself
      -- and the format is expected to be a single string, so the adjacent
      -- literals this comment used to sit above were a portability gamble for
      -- no benefit.
      if old.state = 'held' then
        raise exception 'a held entry is edited through yours_update_held or yours_let_this_return, not by writing over it';
      end if;

      new.state := old.state;
      new.renewal_count := old.renewal_count;
      new.presented_at := old.presented_at;
      new.decide_by := old.decide_by;
      new.held_at := old.held_at;

      if new.body is distinct from old.body then
        -- §3: editing restarts the *current* interval, not the lifecycle
        -- stage. An entry in its first renewal that is edited gets a fresh
        -- twelve weeks, not a demotion to six. Renewal count is preserved
        -- above, and this is the line that depends on it.
        new.ready_at := now() + private.yours_interval(old.renewal_count);
        -- It is living again, and its unanswered question goes with it.
        new.state := 'living';
        new.presented_at := null;
        new.decide_by := null;
      else
        new.ready_at := old.ready_at;
      end if;
    end if;
  end if;

  -- Locked #6, on every path into the table.
  new.unseen_delete_at := new.ready_at + interval '1 year';

  -- A held entry has no pending question. Leaving a stale window on it would
  -- let the sweep delete something a person deliberately made permanent.
  if new.state = 'held' then
    new.presented_at := null;
    new.decide_by := null;
  end if;

  return new;
end;
$$;

revoke all on function private.yours_stamp_entry()
  from public, anon, authenticated;

commit;
