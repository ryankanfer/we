import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

/** Runs from either an owner's explicit deletion or the existing scheduled cleanup
 * worker. Jobs are idempotent; a crash retains the job until all removals finish. */
export async function cleanupIntake(client: SupabaseClient, owner: string | null = null, artifact: string | null = null) {
  const { data, error } = await client.rpc("intake_cleanup_jobs", { p_owner: owner, p_artifact: artifact });
  if (error) return { completed: 0, pending: 1 };
  let completed = 0;
  let pending = 0;
  for (const job of data ?? []) {
    try {
      const prefix = `${job.owner_id}/${job.artifact_id}`;
      let exhausted = false;
      for (let batch = 0; batch < 10; batch++) {
        const list = await client.storage.from("private-originals").list(prefix, { limit: 100 });
        if (list.error) throw new Error("list");
        const paths = (list.data ?? []).map((r: { name: string }) => `${prefix}/${r.name}`);
        if (!paths.length) { exhausted = true; break; }
        if ((await client.storage.from("private-originals").remove(paths)).error) throw new Error("remove");
      }
      if (!exhausted) throw new Error("more cleanup required");
      for (const resource of job.resources ?? []) {
        if ((await client.storage.from(resource.bucket).remove([resource.path])).error) throw new Error("remove");
      }
      if ((await client.rpc("intake_finish_cleanup", { p_owner: job.owner_id, p_id: job.artifact_id })).error) throw new Error("finish");
      completed++;
    } catch { pending++; }
  }
  return { completed, pending };
}
