const assert = require("node:assert/strict");
const M = require("./review-model.js");
const E = require("./review-email.js");
const draft = () => M.sampleState();
const errors = state => M.validate(state).filter(i => i.level === "error");
let count = 0;
function test(name, run) { run(); count++; console.log(`OK ${name}`); }
test("seven fixed sections and a valid concise default", () => {
  assert.equal(M.sections.length, 7);
  assert.deepEqual(errors(draft()), []);
  assert(M.readingWords(draft()) <= 400);
  assert.deepEqual([...E.render(draft()).matchAll(/data-review-section="([^"]+)"/g)].map(m => m[1]), M.sections.map(s => s.id));
});
test("calendar validation rejects impossible dates and accepts leap years", () => {
  for (const date of ["2026-02-29", "2026-04-31", "09/17/2026", "2026-13-01", "0000-01-01", ""]) assert.equal(M.validDate(date), false);
  assert(M.validDate("2028-02-29"));
});
test("row sorting is chronological, stable, and non-mutating", () => {
  const rows = [{ date: "", event: "undated" }, { date: "2026-10-01", event: "later" }, { date: "2026-09-18", time: "11:00", event: "late" }, { date: "2026-09-18", time: "09:00", event: "early" }, { date: "2026-09-18", time: "09:00", event: "tie" }];
  assert.deepEqual(M.sortRows(rows).map(r => r.event), ["early", "tie", "late", "later", "undated"]);
  assert.equal(rows[0].event, "undated");
});
test("required and optional tables remain distinct regardless of dates", () => {
  const state = draft();
  state.actions.required.reverse();
  const html = E.render(state);
  assert(html.indexOf("Quarter readiness checklist", html.indexOf('id="actions"')) < html.indexOf("Learning plan confirmation"));
  assert(html.indexOf('aria-label="Required by date"') < html.indexOf('aria-label="Optional / Recurring"'));
  assert(html.indexOf("NEXT REQUIRED") < html.indexOf('id="scoreboard"'));
});
test("overdue callout is relative to issue date", () => {
  const state = draft();
  state.actions.required[0].date = "2026-09-01";
  assert(E.render(state).includes("OVERDUE AS OF THIS ISSUE"));
  assert(M.validate(state).some(i => i.level === "warning" && i.message.includes("overdue")));
});
test("missing required date and event time zone block export", () => {
  const state = draft();
  state.actions.required[0].date = "";
  state.actions.optional[0].zone = "";
  assert(errors(state).some(i => i.message.includes("due date")));
  assert(errors(state).some(i => i.message.includes("time zone")));
});
test("zero action rows keep the always-present section and explicit empty states", () => {
  const state = draft();
  state.actions.required = []; state.actions.optional = [];
  assert.equal(errors(state).length, 0);
  const html = E.render(state);
  assert(html.includes('id="actions"'));
  assert(html.includes("No required deadlines"));
  assert(!html.includes("NEXT REQUIRED"));
});
test("optional sections can be omitted without deleting content", () => {
  const state = draft();
  state.lead.enabled = false; state.leadership.enabled = false; state.community.enabled = false;
  const html = E.render(state);
  for (const id of ["lead", "leadership", "community"]) assert(!html.includes(`id="${id}"`));
  assert(state.lead.summary.length);
  assert(errors(state).some(i => i.message.includes("omitted section")));
  state.header.teasers[0].target = "signoff";
  assert.equal(errors(state).length, 0);
});
test("empty optional sections disappear rather than showing empty headings", () => {
  const state = draft();
  M.schemas.lead.forEach(f => { state.lead[f.key] = ""; });
  state.leadership.body = ""; state.community.welcome = ""; state.community.awards = ""; state.community.social = "";
  const html = E.render(state);
  for (const id of ["lead", "leadership", "community"]) assert(!html.includes(`id="${id}"`));
});
test("three to four teasers and at most three priorities", () => {
  const state = draft();
  state.header.teasers = state.header.teasers.slice(0, 2);
  state.leadership.priorities = "One\nTwo\nThree\nFour";
  assert(errors(state).some(i => i.message.includes("three or four")));
  assert(errors(state).some(i => i.message.includes("limited to three")));
  assert(E.render(state).includes("Four"));
});
test("authored text is escaped, dangerous URLs never become links or images", () => {
  const state = draft();
  state.lead.summary = '<img src=x onerror="alert(1)">&';
  state.actions.required[0].url = "javascript:alert(1)";
  state.header.bannerUrl = "data:image/svg+xml,<svg/>";
  state.community.socialUrl = "https://user:password@example.com";
  const html = E.render(state);
  assert(html.includes("&lt;img"));
  assert(!html.includes('href="javascript:'));
  assert(!html.includes('src="data:'));
  assert(!html.includes("user:password"));
  assert(errors(state).length >= 3);
});
test("names-only default, optional signoff portraits, never community portraits", () => {
  const state = draft();
  assert.equal((E.render(state).match(/<img /g) || []).length, 1);
  state.signoff.portraitMode = "portraits";
  const html = E.render(state);
  assert.equal((html.match(/<img /g) || []).length, 5);
  assert(!html.slice(html.indexOf('id="community"'), html.indexOf('id="signoff"')).includes("<img"));
});
test("invalid schemas rejected and no optional data silently promoted", () => {
  const state = draft();
  state.signoff.people = [{ name: "Missing fields" }];
  assert(!M.validState(state));
  assert.throws(() => E.render(state), /invalid review/);
});
test("email stays table-based, branded, and lightweight", () => {
  const html = E.render(draft());
  assert(html.includes("microsoft-logo"));
  assert(html.includes("<v:fill"));
  assert(html.includes("<thead>") && html.includes('scope="col"') && html.includes('scope="row"'));
  assert(!/<script|display:\s*(flex|grid)/.test(html));
  assert(Buffer.byteLength(html) < 95 * 1024);
});
console.log(`${count} Review tests passed.`);
