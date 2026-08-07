import { createClient } from "jsr:@supabase/supabase-js@2";

type CleanupJob = {
  id: string;
  object_path: string;
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = request.headers.get("authorization");
  if (!url || !serviceKey || authorization !== `Bearer ${serviceKey}`) {
    return json({ error: "unauthorized" }, 401);
  }

  const client = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await client.rpc("share_claim_cleanup_jobs", {
    p_limit: 25,
  });
  if (error) {
    return json({ error: "claim_failed" }, 500);
  }

  const jobs = (data ?? []) as CleanupJob[];
  if (jobs.length === 0) {
    return json({ claimed: 0, removed: 0, retried: 0 });
  }

  const paths = jobs.map((job) => job.object_path);
  const removal = await client.storage.from("life-resources").remove(paths);
  let completedCount = 0;
  let retryCount = 0;
  for (const job of jobs) {
    // Storage removal is intentionally idempotent. A path already removed by
    // a prior response-lost attempt is still a completed cleanup job.
    const succeeded = !removal.error;
    const result = await client.rpc("share_complete_cleanup_job", {
      p_job: job.id,
      p_succeeded: succeeded,
      p_error_code: succeeded ? null : "storage_remove_failed",
    });
    if (!result.error && succeeded) completedCount += 1;
    if (!result.error && !succeeded) retryCount += 1;
  }

  // No object paths, filenames, hashes, or source content enter diagnostics.
  return json({
    claimed: jobs.length,
    removed: completedCount,
    retried: retryCount,
  });
});
