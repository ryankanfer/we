# Arrival announcement deployment

Sends one fixed sentence to both people's devices at the moment the second
person joins a space, and nothing else, ever. The rule this is built under: **WE
never sends a notification containing news, only ones inviting presence.**

## Secrets

Create a dedicated named Supabase secret API key called `arrival`, store it in
Vault as `arrival_worker_key`, and store the project URL as
`arrival_worker_url`:

```sql
select vault.create_secret('<dedicated sb_secret_ key>', 'arrival_worker_key');
select vault.create_secret('https://<ref>.supabase.co', 'arrival_worker_url');
```

`20260824140000_arrival_notification.sql` schedules the POST once a minute with
that key in the `apikey` header. `verify_jwt` is disabled because modern
`sb_secret_` keys are not JWTs; the function authorizes the `apikey` itself and
accepts only the dedicated key.

## APNs

| Variable           | What                                                  |
| ------------------ | ----------------------------------------------------- |
| `APNS_KEY_ID`      | The .p8 key's id                                      |
| `APNS_TEAM_ID`     | Apple Developer team id                               |
| `APNS_TOPIC`       | The app's bundle id, `com.ryankanfer.WE`              |
| `APNS_PRIVATE_KEY` | The .p8 contents, PEM, newlines intact                |
| `APNS_HOST`        | `api.push.apple.com` for release. Defaults to sandbox |

A development build's device tokens are refused by production APNs and the other
way round, and the failure mode of getting this wrong is silence — which is
indistinguishable from the function working correctly, because silence is what a
working deployment produces for a person who declined notifications. Check
`announced` in the response when verifying.

## What it will not do

- **No retry.** A row is marked delivered before the send, so an interrupted run
  cannot announce twice. An arrival that failed to reach a phone is not
  reattempted: a push that arrives a day late is news about yesterday.
- **No receipt.** Nothing tells either person that the other was notified, or
  when. That would be a report on the other person's timing.
- **No payload.** No name, no couple id, no count, no custom keys, no sound.
- **No push without credentials.** With `APNS_*` unset the function returns
  `skipped` and touches nothing. The ceremony is correct with push absent
  entirely, which is why push was built last.
