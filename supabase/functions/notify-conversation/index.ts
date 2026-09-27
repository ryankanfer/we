import { createClient } from "jsr:@supabase/supabase-js@2";
import { authorizedSecretKey, configuredSecretKeys } from "./auth.ts";
import { configuration, send, isDeadToken } from "./apns.ts";
const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json" } });
Deno.serve(async request => {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const key = authorizedSecretKey(request, configuredSecretKeys(Deno.env.get("SUPABASE_SECRET_KEYS")));
  const url = Deno.env.get("SUPABASE_URL");
  if (!key || !url) return json({ error: "unauthorized" }, 401);
  const apns = configuration(name => Deno.env.get(name));
  if (!apns) return json({ skipped: "apns_not_configured" });
  const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: rows, error } = await client.from("field_chat_notifications").select("couple_id,profile_id,last_message_at,delivered_at").order("last_message_at", { ascending: false }).limit(100);
  if (error) return json({ error: "queue_unavailable" }, 500);
  let sent = 0;
  for (const row of rows ?? []) {
    if (row.delivered_at && row.delivered_at >= row.last_message_at) continue;
    const { data: pref, error: preferenceError } = await client.from("field_chat_preferences").select("read_at,notifications").eq("couple_id", row.couple_id).eq("profile_id", row.profile_id).maybeSingle();
    if (preferenceError) continue;
    const fresh = Date.now() - Date.parse(row.last_message_at) < 60 * 60 * 1000;
    const notify = fresh && pref?.notifications !== false && (!pref?.read_at || pref.read_at < row.last_message_at);
    // Claim by the observed message timestamp; a new arrival cannot be consumed by this older claim.
    let claim = client.from("field_chat_notifications").update({ delivered_at: row.last_message_at }).eq("couple_id", row.couple_id).eq("profile_id", row.profile_id).eq("last_message_at", row.last_message_at);
    claim = row.delivered_at ? claim.eq("delivered_at", row.delivered_at) : claim.is("delivered_at", null);
    const { data: claimed, error: claimError } = await claim.select("profile_id");
    if (claimError || !claimed?.length || !notify) continue;
    const { data: tokens } = await client.from("device_tokens").select("token").eq("profile_id", row.profile_id);
    for (const token of tokens ?? []) {
      try {
        const result = await send(apns, token.token, "Something is waiting for you both in WE.", "chat-" + row.couple_id);
        if (result.ok) sent++;
        else if (isDeadToken(result.status)) await client.from("device_tokens").delete().eq("profile_id", row.profile_id).eq("token", token.token);
      } catch { /* The message itself remains durable; push is a best-effort nudge. */ }
    }
  }
  return json({ sent });
});
