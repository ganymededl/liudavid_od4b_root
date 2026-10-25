import assert from "node:assert/strict";
import test from "node:test";
import {
  buildFoundryRequest,
  validateRecommendation,
  validateRoutingRequest
} from "../src/lib/router.js";

const candidates = [
  {
    id: "fast",
    name: "Fast",
    family: "Test",
    tier: "fast",
    known: "Quick routine work.",
    best: ["Triage"],
    caveat: "Less depth.",
    scores: { reasoning: 5, speed: 10, coding: 5, writing: 6, tools: 6, context: 5 }
  },
  {
    id: "deep",
    name: "Deep",
    family: "Test",
    tier: "power",
    known: "Hard reasoning.",
    best: ["Architecture"],
    caveat: "Slower.",
    scores: { reasoning: 10, speed: 4, coding: 9, writing: 8, tools: 9, context: 9 }
  }
];

function validRequest() {
  return {
    prompt: "Review a production authentication change.",
    platform: "scout",
    priority: "quality",
    stakes: "high",
    context: "medium",
    candidates
  };
}

test("normalizes a bounded routing request", () => {
  const value = validateRoutingRequest(validRequest());
  assert.equal(value.candidates.length, 2);
  assert.equal(value.prompt, "Review a production authentication change.");
});

test("supports a platform with one eligible managed model", () => {
  const value = validRequest();
  value.platform = "cowork";
  value.candidates = [candidates[0]];
  assert.deepEqual(validateRoutingRequest(value).candidates.map(item => item.id), ["fast"]);
});

test("preserves exact case-sensitive model IDs", () => {
  const value = validRequest();
  value.candidates = [...candidates, { ...candidates[0], id: "FAST" }];
  assert.deepEqual(validateRoutingRequest(value).candidates.map(item => item.id), ["fast", "deep", "FAST"]);
});

test("rejects duplicate exact model IDs", () => {
  const value = validRequest();
  value.candidates = [...candidates, { ...candidates[0] }];
  assert.throws(() => validateRoutingRequest(value), /unique and case-sensitive/);
});

test("builds a strict schema constrained to eligible IDs", () => {
  const input = validateRoutingRequest(validRequest());
  const request = buildFoundryRequest(input, "router-deployment");
  assert.equal(request.model, "router-deployment");
  assert.deepEqual(
    request.response_format.json_schema.schema.properties.primaryId.enum,
    ["fast", "deep"]
  );
  assert.match(request.messages[0].content, /untrusted data/);
});

test("rejects a model response that invents an ID", () => {
  assert.throws(() => validateRecommendation({
    primaryId: "invented",
    confidence: "high",
    rationale: "Reason",
    matchedSignals: ["security"],
    lighterId: "fast",
    lighterReason: "Faster",
    upgradeId: "deep",
    upgradeReason: "Deeper",
    switchRule: "Switch if needed",
    reasoningEffort: "high"
  }, candidates), /ineligible primary model/);
});

test("accepts a recommendation using eligible IDs", () => {
  const recommendation = validateRecommendation({
    primaryId: "deep",
    confidence: "high",
    rationale: "The task is consequential and code intensive.",
    matchedSignals: ["production", "authentication"],
    lighterId: "fast",
    lighterReason: "Use for a first-pass summary.",
    upgradeId: "deep",
    upgradeReason: "Already the strongest eligible option.",
    switchRule: "Switch if latency becomes more important.",
    reasoningEffort: "high"
  }, candidates);
  assert.equal(recommendation.primaryId, "deep");
});

test("rejects a slower model as the lighter option", () => {
  assert.throws(() => validateRecommendation({
    primaryId: "fast",
    confidence: "high",
    rationale: "Fast is enough.",
    matchedSignals: ["speed"],
    lighterId: "deep",
    lighterReason: "Incorrectly described as lighter.",
    upgradeId: "deep",
    upgradeReason: "Use for more depth.",
    switchRule: "Switch when the task gets harder.",
    reasoningEffort: "low"
  }, candidates), /slower model as the lighter option/);
});
