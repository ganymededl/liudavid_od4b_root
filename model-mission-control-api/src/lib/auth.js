import { createRemoteJWKSet, jwtVerify } from "jose";
import { HttpError } from "./errors.js";

const jwksByTenant = new Map();

function requiredSetting(settings, name) {
  const value = settings[name]?.trim();
  if (!value) throw new HttpError(500, "configuration_error", `${name} is not configured.`);
  return value;
}

export function readBearerToken(request) {
  const authorization = request.headers.get("authorization") || "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) throw new HttpError(401, "unauthorized", "A DIAx access token is required.");
  return match[1];
}

function getJwks(tenantId) {
  if (!jwksByTenant.has(tenantId)) {
    const url = new URL(`https://login.microsoftonline.com/${tenantId}/discovery/v2.0/keys`);
    jwksByTenant.set(tenantId, createRemoteJWKSet(url));
  }
  return jwksByTenant.get(tenantId);
}

export async function authorize(request, settings = process.env) {
  const tenantId = requiredSetting(settings, "ENTRA_TENANT_ID");
  const audience = requiredSetting(settings, "ENTRA_API_CLIENT_ID");
  const allowedUserObjectId = requiredSetting(settings, "ALLOWED_USER_OBJECT_ID");
  const token = readBearerToken(request);

  try {
    const { payload } = await jwtVerify(token, getJwks(tenantId), {
      issuer: `https://login.microsoftonline.com/${tenantId}/v2.0`,
      audience: [audience, `api://${audience}`]
    });
    const scopes = new Set(String(payload.scp || "").split(" ").filter(Boolean));
    if (payload.tid !== tenantId || payload.oid !== allowedUserObjectId || !scopes.has("access_as_user")) {
      throw new HttpError(403, "forbidden", "This DIAx identity is not authorized for Model Mission Control.");
    }
    return payload;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError(401, "unauthorized", "The DIAx access token is invalid or expired.");
  }
}
