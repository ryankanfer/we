// APNs, with the smallest surface that will send one fixed sentence.
//
// The provider token is an ES256 JWT signed with the .p8 key, and Apple caps
// how often a new one may be minted, so it is cached for the life of the
// isolate and reused across every arrival in a run.

const encoder = new TextEncoder();

const base64url = (bytes: Uint8Array): string =>
  btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

const base64urlText = (value: string): string =>
  base64url(encoder.encode(value));

export type APNsConfiguration = {
  keyID: string;
  teamID: string;
  topic: string;
  host: string;
  privateKeyPEM: string;
};

export const configuration = (
  env: (name: string) => string | undefined,
): APNsConfiguration | null => {
  const keyID = env("APNS_KEY_ID");
  const teamID = env("APNS_TEAM_ID");
  const topic = env("APNS_TOPIC");
  const privateKeyPEM = env("APNS_PRIVATE_KEY");
  // Sandbox unless a deployment says otherwise. A development build's tokens
  // are refused by production APNs and the other way round, and the failure
  // mode of guessing wrong is silence — which this product cannot tell apart
  // from working correctly.
  const host = env("APNS_HOST") ?? "api.sandbox.push.apple.com";
  if (!keyID || !teamID || !topic || !privateKeyPEM) return null;
  return { keyID, teamID, topic, host, privateKeyPEM };
};

const importKey = async (pem: string): Promise<CryptoKey> => {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
};

let cached: { token: string; issuedAt: number } | null = null;

export const providerToken = async (
  config: APNsConfiguration,
  now: number = Date.now(),
): Promise<string> => {
  // Apple rejects tokens older than an hour and refuses ones minted more often
  // than every twenty minutes. Fifty minutes sits inside both.
  if (cached && now - cached.issuedAt < 50 * 60 * 1000) return cached.token;

  const issuedAt = Math.floor(now / 1000);
  const header = base64urlText(
    JSON.stringify({ alg: "ES256", kid: config.keyID }),
  );
  const payload = base64urlText(
    JSON.stringify({ iss: config.teamID, iat: issuedAt }),
  );
  const key = await importKey(config.privateKeyPEM);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(`${header}.${payload}`),
  );
  const token = `${header}.${payload}.${base64url(new Uint8Array(signature))}`;
  cached = { token, issuedAt: now };
  return token;
};

/// One fixed sentence, to one device.
///
/// `collapse-id` is the couple, so a device that somehow receives two of these
/// shows one. Apple deduplicates on it, which is a second belt to the
/// uniqueness constraint's braces.
export const send = async (
  config: APNsConfiguration,
  token: string,
  body: string,
  collapseID: string,
): Promise<{ ok: boolean; status: number }> => {
  const jwt = await providerToken(config);
  const response = await fetch(`https://${config.host}/3/device/${token}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${jwt}`,
      "apns-topic": config.topic,
      "apns-push-type": "alert",
      "apns-collapse-id": collapseID.slice(0, 64),
      "content-type": "application/json",
    },
    // No badge, no sound, no thread, no category, no custom keys. WE has no
    // sound, never speaks in counts, and a payload with room in it is a
    // payload somebody will eventually put news into.
    body: JSON.stringify({ aps: { alert: { body } } }),
  });
  // The body is read and thrown away rather than left unconsumed, which leaks
  // a connection per arrival in Deno.
  await response.text();
  return { ok: response.ok, status: response.status };
};

/// Whether Apple is telling us this device is gone for good.
///
/// The only failure worth acting on. Everything else is silence by design.
export const isDeadToken = (status: number): boolean =>
  status === 410 || status === 400;
