import test from "node:test";
import assert from "node:assert/strict";
import { validateEscapeScoreRequest } from "../src/lib/escape-room.js";

test("accepts valid escape-room scoring payload", () => {
  const input = validateEscapeScoreRequest({
    mode: "he",
    role: { id: "finance", name: "Finance" },
    assignment: { title: "Budget review", details: "Create options with constraints." },
    taskIndex: 1,
    learnerPrompt: "You are finance lead. Return a table with options and compliance constraints."
  });
  assert.equal(input.mode, "he");
  assert.equal(input.roleId, "finance");
});

test("rejects unsupported mode", () => {
  assert.throws(
    () =>
      validateEscapeScoreRequest({
        mode: "sales",
        role: { id: "finance", name: "Finance" },
        assignment: { title: "Budget review", details: "Create options with constraints." },
        taskIndex: 1,
        learnerPrompt: "Prompt text"
      }),
    /mode must be he or slg/
  );
});
