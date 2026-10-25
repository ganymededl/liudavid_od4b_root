import { ManagedIdentityCredential } from "@azure/identity";
import { HttpError } from "./errors.js";
import { buildFoundryRequest, validateRecommendation } from "./router.js";

let credential;

function requiredSetting(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new HttpError(500, "configuration_error", `${name} is not configured.`);
  return value;
}

function managedIdentityCredential() {
  credential ||= new ManagedIdentityCredential();
  return credential;
}

export async function assessWithFoundry(input) {
  const endpoint = requiredSetting("AZURE_OPENAI_ENDPOINT").replace(/\/+$/, "");
  const deploymentName = requiredSetting("AZURE_OPENAI_DEPLOYMENT");
  const accessToken = await managedIdentityCredential().getToken(
    "https://cognitiveservices.azure.com/.default"
  );
  if (!accessToken?.token) {
    throw new HttpError(502, "foundry_authentication_failed", "Managed identity could not access Azure AI Foundry.");
  }

  const response = await fetch(`${endpoint}/openai/v1/chat/completions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken.token}`,
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
