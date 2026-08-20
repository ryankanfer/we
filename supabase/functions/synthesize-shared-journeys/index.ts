import { createClient } from "jsr:@supabase/supabase-js@2";
import { authorizedSecretKey, configuredSecretKeys } from "./auth.ts";
import {
  modelResponse,
  PrivateResponse,
  SynthesisResult,
  synthesisSchema,
  systemPrompt,
  validateSynthesis,
} from "./synthesis.ts";

type Job = { insight_id: string };
type InsightRow = {
  id: string;
  title: string;
  options: string[];
  context_snapshot: { evidence?: string[] } | null;
};
type ResponseRow = {
  profile_id: string;
  choice: string;
  note: string | null;
  status: string;
  ai_processing_consented_at: string | null;
  ai_processing_consent_version: string | null;
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

const outputText = (response: Record<string, unknown>): string | null => {
  if (typeof response.output_text === "string") return response.output_text;
  const output = Array.isArray(response.output) ? response.output : [];
  for (const item of output as Array<Record<string, unknown>>) {
    if (item.type !== "message" || !Array.isArray(item.content)) continue;
    for (const part of item.content as Array<Record<string, unknown>>) {
      if (part.type === "output_text" && typeof part.text === "string") {
        return part.text;
      }
    }
  }
  return null;
};

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceKeys = configuredSecretKeys(
    Deno.env.get("SUPABASE_SECRET_KEYS"),
  );
  const serviceKey = authorizedSecretKey(request, serviceKeys);
  const openAIKey = Deno.env.get("OPENAI_API_KEY");
  const model = Deno.env.get("OPENAI_MODEL") ?? "gpt-5.6-luna";
  if (!supabaseURL || !serviceKey) {
    return json({ error: "unauthorized" }, 401);
  }
  // Do not claim work if deployment privacy/configuration is incomplete.
  if (!openAIKey) return json({ error: "synthesis_not_configured" }, 503);

  const client = createClient(supabaseURL, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const claimed = await client.rpc("claim_journey_synthesis_jobs", { p_limit: 10 });
  if (claimed.error) return json({ error: "claim_failed" }, 500);

  let completed = 0;
  let retried = 0;
  for (const job of (claimed.data ?? []) as Job[]) {
    try {
      const [insightResult, responsesResult] = await Promise.all([
        client.from("insights")
          .select("id,title,options,context_snapshot")
          .eq("id", job.insight_id).single(),
        // `note` is read but never forwarded to the model. It exists here
        // only so `validateSynthesis` can assert no note text came back in
        // the output — the tripwire that proves the exclusion held. Removing
        // it from this select would weaken the check, not strengthen privacy.
        client.from("responses")
          .select(
            "profile_id,choice,note,status,ai_processing_consented_at,ai_processing_consent_version",
          )
          .eq("insight_id", job.insight_id)
          .eq("status", "submitted")
          .not("ai_processing_consented_at", "is", null)
          .order("profile_id"),
      ]);
      if (insightResult.error || responsesResult.error) throw new Error("source_read");
      const insight = insightResult.data as InsightRow;
      const responseRows = (responsesResult.data ?? []) as ResponseRow[];
      if (
        responseRows.length !== 2 ||
        responseRows.some((value) =>
          !value.ai_processing_consented_at ||
          value.ai_processing_consent_version !== "2026-08-20"
        )
      ) {
        throw new Error("response_consent");
      }

      const responses: PrivateResponse[] = responseRows.map((value) => ({
        choice: value.choice,
        note: value.note,
      }));
      const evidence = (insight.context_snapshot?.evidence ?? []).slice(0, 3);
      const source = { question: insight.title, evidence, responses };
      const apiResponse = await fetch("https://api.openai.com/v1/responses", {
        method: "POST",
        headers: {
          authorization: `Bearer ${openAIKey}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          model,
          store: false,
          reasoning: { effort: "low", context: "current_turn" },
          max_output_tokens: 900,
          input: [
            { role: "system", content: systemPrompt },
            {
              role: "user",
              // Only `choice` crosses. Notes are deliberately absent from
              // this body — the guarantee in the private-to-shared contract is
              // that a model cannot leak writing it never received, not that a
              // validator will catch it on the way out.
              content: JSON.stringify({
                question: insight.title,
                choices: insight.options,
                frozen_shared_evidence: evidence,
                response_a: modelResponse(responses[0]),
                response_b: modelResponse(responses[1]),
              }),
            },
          ],
          text: {
            format: {
              type: "json_schema",
              name: "shared_journey_proposal",
              strict: true,
              schema: synthesisSchema,
            },
          },
        }),
      });
      if (!apiResponse.ok) throw new Error(`provider_${apiResponse.status}`);
      const provider = await apiResponse.json() as Record<string, unknown>;
      const text = outputText(provider);
      if (!text) throw new Error("missing_output");
      const result = JSON.parse(text) as SynthesisResult;
      const validationError = validateSynthesis(result, source);
      if (validationError) throw new Error(`validation_${validationError}`);

      const saved = await client.rpc("complete_journey_synthesis", {
        p_insight: job.insight_id,
        p_result: result,
        p_version: `openai-responses:${model}:v1`,
      });
      if (saved.error) throw new Error("save_result");
      completed += 1;
    } catch (error) {
      const code = error instanceof Error ? error.message : "unknown";
      const failed = await client.rpc("fail_journey_synthesis_job", {
        p_insight: job.insight_id,
        p_error_code: code.slice(0, 80),
      });
      if (!failed.error) retried += 1;
    }
  }

  // No source or generated content enters logs or the response body.
  return json({ claimed: (claimed.data ?? []).length, completed, retried });
});
