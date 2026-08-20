# Shared journey synthesis deployment

Configure `OPENAI_API_KEY` and optionally `OPENAI_MODEL`. Create a dedicated named
Supabase secret API key called `synthesis`, store that key in Vault as
`synthesis_worker_key`, and schedule a POST with the key in the `apikey` header
every minute. `verify_jwt` is disabled because modern `sb_secret_` keys are not
JWTs; the function authorizes the `apikey` itself and accepts only the dedicated
key. It fails closed when that named key is absent; the project-wide default and
legacy service-role keys are never accepted. The function claims jobs idempotently
and returns content-free counts only.

The OpenAI project must be approved and configured for Zero Data Retention. The
request also sends `store: false`; that disables Responses application-state
storage, while ZDR is what excludes customer content from abuse-monitoring logs.
Do not enable Edge Function request-body logging.
