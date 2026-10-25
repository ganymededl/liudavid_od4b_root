import { app } from "@azure/functions";
import { authorize } from "../lib/auth.js";
import { HttpError } from "../lib/errors.js";
import { assessWithFoundry } from "../lib/foundry.js";
import { validateRoutingRequest } from "../lib/router.js";

function allowedOrigins() {
  return new Set(
    String(process.env.ALLOWED_ORIGINS || "")
      .split(",")
      .map(origin => origin.trim())
      .filter(Boolean)
  );
}

function corsHeaders(origin) {
  const headers = {
    "Cache-Control": "no-store",
    "Content-Type": "application/json; charset=utf-8",
    "Vary": "Origin"
  };
  if (origin && allowedOrigins().has(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
    headers["Access-Control-Allow-Headers"] = "authorization,content-type";
    headers["Access-Control-Allow-Methods"] = "POST,OPTIONS";
  }
  return headers;
}

function json(status, body, origin) {
  return { status, headers: corsHeaders(origin), jsonBody: body };
}

app.http("recommend", {
  methods: ["POST", "OPTIONS"],
  authLevel: "anonymous",
  route: "recommend",
  handler: async (request, context) => {
    const origin = request.headers.get("origin") || "";
    if (origin && !allowedOrigins().has(origin)) {
      return json(403, { error: "origin_not_allowed", message: "This site is not allowed to call the API." }, "");
    }
    if (request.method === "OPTIONS") {
      return { status: 204, headers: corsHeaders(origin) };
    }

    try {
      await authorize(request);
      let body;
      try {
        body = await request.json();
      } catch {
        throw new HttpError(400, "invalid_json", "The request body must be valid JSON.");
      }
      const input = validateRoutingRequest(body);
      const recommendation = await assessWithFoundry(input);
      return json(200, {
        ...recommendation,
        source: "Azure AI Foundry via managed identity",
        assessedAt: new Date().toISOString()
      }, origin);
    } catch (error) {
      const handled = error instanceof HttpError
        ? error
        : new HttpError(500, "internal_error", "The AI assessment could not be completed.");
      if (handled.status >= 500) {
        context.error("Model Mission Control assessment failed.", {
          code: handled.code,
          name: error?.name || "Error"
        });
      }
      return json(handled.status, { error: handled.code, message: handled.message }, origin);
    }
  }
});
