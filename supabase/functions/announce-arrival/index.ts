// The arrival, announced to two phones, once.
//
// Driven by `cron.schedule('we-announce-arrival')` a minute at a time. Reads
// the queue a trigger fills on redemption, sends one fixed sentence to every
// device the two people have registered, and marks the row delivered whatever
// Apple says.
//
// **Whatever Apple says**, deliberately. Delivery failure is silent and
// non-blocking: presence plus the aggregate RPC drive the ceremony, so a
// dropped push costs a convenience and never correctness. Retrying would mean
// a phone that is off for a day gets woken at the moment it comes back, about
// something that happened yesterday, which is news.
//
// The payload carries `arrivalNotification` and nothing else. No name, no
// couple, no count, no custom keys. See the migration's header for the rule,
// and `WEArrivalNotificationTests` for the assertion that this string and the
// app's own are the same string.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { authorizedSecretKey, configuredSecretKeys } from "./auth.ts";
import { configuration, isDeadToken, send } from "./apns.ts";

/// The one sentence WE is allowed to say from a lock screen.
///
/// It invites presence and reports nothing. Somebody reading it over a
/// shoulder learns that the person owns WE, which they could see from the icon.
export const ARRIVAL_NOTIFICATION = "WE is ready for you both.";

type Arrival = { couple_id: string };
type MemberRow = { profile_id: string };
type TokenRow = { profile_id: string; token: string };

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceKey = authorizedSecretKey(
    request,
    configuredSecretKeys(Deno.env.get("SUPABASE_SECRET_KEYS")),
  );
  if (!supabaseURL || !serviceKey) return json({ error: "unauthorized" }, 401);

  const apns = configuration((name) => Deno.env.get(name));
  // Not an error. A deployment without APNs credentials is a deployment
  // without push, and the product works without push — that is why push was
  // built last. Leaving the queue untouched means the rows are here if it is
  // ever configured, and nothing is ever sent about an old arrival because
  // nothing here retries.
  if (!apns) return json({ skipped: "apns_not_configured" }, 200);

  const client = createClient(supabaseURL, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const pending = await client
    .from("arrival_notifications")
    .select("couple_id")
    .is("delivered_at", null)
    .order("created_at")
    .limit(25);
  if (pending.error) return json({ error: "queue_unreadable" }, 500);

  let announced = 0;
  for (const arrival of (pending.data ?? []) as Arrival[]) {
    // Marked first, and only then sent. A worker that sends before it marks
    // will send twice the moment it is interrupted in between, and two people
    // being told twice that they have arrived is worse than not being told.
    const claimed = await client
      .from("arrival_notifications")
      .update({ delivered_at: new Date().toISOString() })
      .eq("couple_id", arrival.couple_id)
      .is("delivered_at", null)
      .select("couple_id");
    if (claimed.error || (claimed.data ?? []).length === 0) continue;

    const members = await client
      .from("couple_members")
      .select("profile_id")
      .eq("couple_id", arrival.couple_id);
    if (members.error) continue;

    const ids = ((members.data ?? []) as MemberRow[]).map((m) => m.profile_id);
    if (ids.length === 0) continue;

    const tokens = await client
      .from("device_tokens")
      .select("profile_id,token")
      .in("profile_id", ids);
    if (tokens.error) continue;

    for (const row of (tokens.data ?? []) as TokenRow[]) {
      const result = await send(
        apns,
        row.token,
        ARRIVAL_NOTIFICATION,
        arrival.couple_id,
      );
      if (result.ok) {
        announced += 1;
        continue;
      }
      // The one failure worth acting on: the device is gone, and keeping its
      // token means carrying a record of a phone somebody no longer has.
      if (isDeadToken(result.status)) {
        await client
          .from("device_tokens")
          .delete()
          .eq("profile_id", row.profile_id)
          .eq("token", row.token);
      }
    }
  }

  return json({ announced });
});
