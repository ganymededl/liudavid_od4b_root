import assert from "node:assert/strict";
import test from "node:test";
import { getManagedIdentityToken } from "../src/lib/foundry.js";

test("requests an Azure OpenAI token from the Functions managed identity endpoint", async () => {
  let capturedUrl;
  let capturedOptions;
  const token = await getManagedIdentityToken({
    IDENTITY_ENDPOINT: "http://127.0.0.1:41741/msi/token",
    IDENTITY_HEADER: "identity-secret"
  }, async (url, options) => {
    capturedUrl = url;
    capturedOptions = options;
    return {
      ok: true,
      async json() {
        return { access_token: "managed-identity-token" };
      }
    };
  });

  assert.equal(token, "managed-identity-token");
  assert.equal(capturedUrl.searchParams.get("api-version"), "2019-08-01");
  assert.equal(capturedUrl.searchParams.get("resource"), "https://cognitiveservices.azure.com");
  assert.equal(capturedOptions.headers["X-IDENTITY-HEADER"], "identity-secret");
});

test("rejects a managed identity response without an access token", async () => {
  await assert.rejects(
    getManagedIdentityToken({
      IDENTITY_ENDPOINT: "http://127.0.0.1:41741/msi/token",
      IDENTITY_HEADER: "identity-secret"
    }, async () => ({
      ok: true,
      async json() {
        return {};
      }
    })),
    error => error.code === "foundry_authentication_failed" && error.status === 502
  );
});
