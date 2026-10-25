import { HttpError } from "./errors.js";
import { buildFoundryRequest, validateRecommendation } from "./router.js";

function requiredSetting(name, settings = process.env) {
  const value = settings[name]?.trim();
  if (!value) throw new HttpError(500, "configuration_error", `${name} is not configured.`);
  return value;
}

export async function getManagedIdentityToken(settings = process.env, fetchImpl = fetch) {
  const endpoint = new URL(requiredSetting("IDENTITY_ENDPOINT", settings));
  endpoint.searchParams.set("api-version", "2019-08-01");
  endpoint.searchParams.set("resource", "https://cognitiveservices.azure.com");
  const response = await fetchImpl(endpoint, {
    headers: {
      "X-IDENTITY-HEADER": requiredSetting("IDENTITY_HEADER", settings)
    },
    signal: AbortSignal.timeout(10000)
  });
  if (!response.ok) {
    throw new HttpError(502, "foundry_authentication_failed", "Managed identity could not access Azure OpenAI.");
  }
  const payload = await response.json();
  if (typeof payload?.access_token !== "string" || !payload.access_token) {
    throw new HttpError(502, "foundry_authentication_failed", "Managed identity returned no Azure OpenAI access token.");
  }
  return payload.access_token;
}

export async function assessWithFoundry(input) {
  const endpoint = requiredSetting("AZURE_OPENAI_ENDPOINT").replace(/\/+$/, "");
  const deploymentName = requiredSetting("AZURE_OPENAI_DEPLOYMENT");
  const accessToken = await getManagedIdentityToken();

  const response = await fetch(`${endpoint}/openai/v1/chat/completions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(buildFoundryRequest(input, deploymentName)),
    signal: AbortSignal.timeout(60000)
  });
  if (!response.ok) {
    throw new HttpError(
      502,
      "foundry_request_failed",
      `Azure AI Foundry could not complete the assessment (HTTP ${response.status}).`
    );
  }
  const payload = await response.json();
  const content = payload?.choices?.[0]?.message?.content;
  if (typeof content !== "string") {
    throw new HttpError(502, "invalid_model_response", "Azure AI Foundry returned no recommendation.");
  }
  let recommendation;
  try {
    recommendation = JSON.parse(content);
  } catch {
    throw new HttpError(502, "invalid_model_response", "Azure AI Foundry returned invalid JSON.");
  }
  return validateRecommendation(recommendation, input.candidates);
}
