import { HttpError } from "./errors.js";
import { getManagedIdentityToken } from "./foundry.js";

const MODES = new Set(["he", "slg", "med"]);

function boundedString(value, name, maxLength, minLength = 1) {
  if (typeof value !== "string") {
    throw new HttpError(400, "invalid_request", `${name} must be a string.`);
  }
  const normalized = value.trim();
  if (normalized.length < minLength || normalized.length > maxLength) {
    throw new HttpError(400, "invalid_request", `${name} must contain ${minLength}-${maxLength} characters.`);
  }
  return normalized;
}

export function validateEscapeScoreRequest(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new HttpError(400, "invalid_request", "The request body must be a JSON object.");
  }
  if (!MODES.has(body.mode)) {
    throw new HttpError(400, "invalid_request", "mode must be he, slg, or med.");
  }
  const roleId = boundedString(body.role?.id, "role.id", 80);
  const roleName = boundedString(body.role?.name, "role.name", 120);
  const assignmentTitle = boundedString(body.assignment?.title, "assignment.title", 240);
  const assignmentDetails = boundedString(body.assignment?.details, "assignment.details", 1200);
  const learnerPrompt = boundedString(body.learnerPrompt, "learnerPrompt", 12000, 3);
  const taskIndex = Number(body.taskIndex);
  if (!Number.isInteger(taskIndex) || taskIndex < 0 || taskIndex > 20) {
    throw new HttpError(400, "invalid_request", "taskIndex must be an integer between 0 and 20.");
  }
  return {
    mode: body.mode,
    roleId,
    roleName,
    assignmentTitle,
    assignmentDetails,
    learnerPrompt,
    taskIndex
  };
}

function buildEscapeScoringRequest(input, deploymentName) {
  const systemPrompt = [
    "You are Prompt Escape Room evaluator.",
    "Evaluate learner prompts for Higher Ed, State/Local Government, and Medical Center back-office scenarios.",
    "Score the learner prompt from 0-100 based on role definition, requested result format, practical limits, step-by-step usability, and handling of unknowns.",
    "Write feedback in plain everyday language for non-technical users.",
    "Avoid jargon like role clarity, constraints, output shape, actionability, assumptions, optimization, or model behavior.",
    "Return 2-5 short coaching bullets. Each bullet must be one sentence and directly tell the learner what to improve next.",
    "Set label to one of: Excellent prompt., Great start., Good draft; needs a few fixes., Needs more detail.",
    "Return strict JSON only in this format:",
    "{\"score\": number 0-100, \"label\": string, \"feedback\": string[] }"
  ].join(" ");

  const userData = {
    mode: input.mode,
    role: { id: input.roleId, name: input.roleName },
    assignment: { title: input.assignmentTitle, details: input.assignmentDetails },
    taskIndex: input.taskIndex,
    learnerPrompt: input.learnerPrompt
  };

  return {
    model: deploymentName,
    messages: [
      { role: "system", content: systemPrompt },
      { role: "user", content: JSON.stringify(userData) }
    ],
    max_tokens: 800
  };
}

function validateEscapeScore(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpError(502, "invalid_model_response", "The scorer did not return a JSON object.");
  }
  const numericScore = Number(value.score);
  if (!Number.isFinite(numericScore) || numericScore < 0 || numericScore > 100) {
    throw new HttpError(502, "invalid_model_response", "The scorer returned an invalid score.");
  }
  if (typeof value.label !== "string" || !value.label.trim() || value.label.length > 160) {
    throw new HttpError(502, "invalid_model_response", "The scorer returned an invalid label.");
  }
  if (!Array.isArray(value.feedback) || value.feedback.length < 1 || value.feedback.length > 6) {
    throw new HttpError(502, "invalid_model_response", "The scorer returned invalid feedback.");
  }
  const feedback = value.feedback.map((line, index) =>
    boundedString(line, `feedback[${index}]`, 240)
  );
  return {
    score: Math.round(numericScore),
    label: value.label.trim(),
    feedback
  };
}

export async function assessEscapeScore(input) {
  const endpoint = String(process.env.ESCAPE_AOAI_ENDPOINT || "").trim().replace(/\/+$/, "");
  const deploymentName = String(process.env.ESCAPE_AOAI_DEPLOYMENT || "").trim();
  if (!endpoint || !deploymentName) {
    throw new HttpError(500, "configuration_error", "Escape room Foundry settings are not configured.");
  }

  const accessToken = await getManagedIdentityToken();
  const response = await fetch(`${endpoint}/openai/v1/chat/completions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(buildEscapeScoringRequest(input, deploymentName)),
    signal: AbortSignal.timeout(60000)
  });

  if (!response.ok) {
    throw new HttpError(
      502,
      "foundry_request_failed",
      `Azure AI Foundry could not score the prompt (HTTP ${response.status}).`
    );
  }
  const payload = await response.json();
  const content = payload?.choices?.[0]?.message?.content;
  if (typeof content !== "string") {
    throw new HttpError(502, "invalid_model_response", "Azure AI Foundry returned no scoring content.");
  }
  let parsed;
  try {
    parsed = JSON.parse(content);
  } catch {
    const match = content.match(/\{[\s\S]*\}/);
    if (!match) {
      throw new HttpError(502, "invalid_model_response", "Azure AI Foundry returned invalid JSON.");
    }
    try {
      parsed = JSON.parse(match[0]);
    } catch {
      throw new HttpError(502, "invalid_model_response", "Azure AI Foundry returned invalid JSON.");
    }
  }
  return validateEscapeScore(parsed);
}
