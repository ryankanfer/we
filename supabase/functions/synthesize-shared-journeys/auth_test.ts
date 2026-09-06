import { authorizedSecretKey, configuredSecretKeys } from "./auth.ts";

const assertEquals = (actual: unknown, expected: unknown) => {
  if (actual !== expected) {
    throw new Error(`Expected ${String(expected)}, received ${String(actual)}`);
  }
};

Deno.test("a named synthesis key excludes every broader service key", () => {
  const keys = configuredSecretKeys(
    JSON.stringify({ default: "sb_secret_default", synthesis: "sb_secret_worker" }),
  );
  assertEquals(keys.length, 1);
  assertEquals(keys[0], "sb_secret_worker");
});

Deno.test("a service call authenticates through apikey, never bearer", () => {
  const keys = ["sb_secret_worker"];
  const bearerOnly = new Request("https://example.invalid", {
    headers: { authorization: "Bearer sb_secret_worker" },
  });
  const serviceCall = new Request("https://example.invalid", {
    headers: { apikey: "sb_secret_worker" },
  });

  assertEquals(authorizedSecretKey(bearerOnly, keys), null);
  assertEquals(authorizedSecretKey(serviceCall, keys), "sb_secret_worker");
});

Deno.test("missing synthesis key fails closed", () => {
  assertEquals(
    configuredSecretKeys(JSON.stringify({ default: "sb_secret_default" })).length,
    0,
  );
  assertEquals(configuredSecretKeys(undefined).length, 0);
  assertEquals(configuredSecretKeys("not-json").length, 0);
});
