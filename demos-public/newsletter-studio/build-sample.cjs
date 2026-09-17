const fs = require("node:fs");
const path = require("node:path");
const { sampleState, validate, readingWords } = require("./review-model.js");
const { render } = require("./review-email.js");

// Always build from fictional defaults, never from a browser's saved draft.
const sample = sampleState();
sample.header.notice += " Not an official Microsoft communication.";
const errors = validate(sample).filter(issue => issue.level === "error");
if (errors.length) throw new Error(JSON.stringify(errors));
const html = render(sample);
fs.writeFileSync(path.join(__dirname, "sample.html"), html, "utf8");
console.log(`Built sample.html: 7 fixed sections, ${readingWords(sample)} content words, ${(Buffer.byteLength(html) / 1024).toFixed(1)} KB.`);
