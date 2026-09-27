import { createClient } from "jsr:@supabase/supabase-js@2";
import { cleanupIntake } from "../_shared/intake-cleanup.ts";

// No source text, URL, bytes, or error bodies enter diagnostics.
Deno.serve(async (request: Request) => {
  const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
    status, headers: { "Content-Type": "application/json" },
  });
  if (request.method !== "POST") return reply({ error: "method" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const authorization = request.headers.get("authorization") ?? "";
  const token = authorization.replace(/^Bearer /i, "");
  const { data: auth } = await admin.auth.getUser(token);
  if (!auth.user) return reply({ error: "authentication" }, 401);
  const owner = auth.user.id;
  const scoped = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authorization } }, auth: { persistSession: false },
  });
  try {
    const body = await request.json();
    if (body.action === "verify") {
      if (!["private-originals", "life-resources"].includes(body.bucket) || typeof body.path !== "string") return reply({ error: "resource" }, 400);
      if (body.bucket === "private-originals" && body.path.split("/")[0] !== owner) return reply({ error: "owner" }, 403);
      if (body.bucket === "life-resources") {
        const sessionID = body.path.split("/")[1];
        const { data: session, error } = await admin.from("share_publication_sessions")
          .select("created_by,expected_resources,state").eq("id", sessionID).single();
        if (error || session.created_by !== owner || session.state !== "created" ||
            !session.expected_resources.some((r: {object_path: string}) => r.object_path === body.path)) return reply({ error: "session" }, 403);
      }
      const { data, error } = await scoped.storage.from(body.bucket).download(body.path);
      if (error || !data || data.size > 67108864) return reply({ error: "download" }, 409);
      const digest = await crypto.subtle.digest("SHA-256", await data.arrayBuffer());
      const sha = Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, "0")).join("");
      if (sha !== body.sha256 || data.size !== body.bytes) return reply({ error: "digest" }, 409);
      const stored = await admin.rpc("intake_record_verification", { p_owner: owner, p_bucket: body.bucket, p_path: body.path, p_sha256: sha, p_bytes: data.size });
      if (stored.error) return reply({ error: "verification" }, 409);
      return reply({ verified: true });
    }
    if (body.action === "delete") {
      const deleted = await scoped.rpc("intake_delete_everywhere", { p_id: body.id });
      if (deleted.error) return reply({ error: "deletion" }, 409);
    } else if (body.action !== "cleanup") return reply({ error: "action" }, 400);
    const cleanup = await cleanupIntake(admin, owner, body.action === "delete" ? body.id : null);
    if (cleanup.pending) return reply({ error: "cleanup_pending" }, 503);
    return reply({ completed: true });
  } catch { return reply({ error: "retry_required" }, 503); }
});
