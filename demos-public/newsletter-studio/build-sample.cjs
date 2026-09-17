const fs = require("node:fs");
const path = require("node:path");
const { sampleState } = require("./app.js");
const { render } = require("./email.js");

// Always build from fictional defaults, never from a browser's saved draft.
const sample = sampleState();
sample.masthead.edition = "September 2026 | Demo edition";
sample.masthead.bannerCaption = "DEMO EDITION. FICTIONAL STORIES. REAL POSSIBILITIES.";
sample.sections.forEach((section, index) => { section.id = `s-demo-${index + 1}`; });
sample.sections[0].body = "PUBLIC DESIGN SAMPLE: All people, organizations, quotes, and results in this edition are fictional. Portraits are original illustrations, not real team members.\n\n" + sample.sections[0].body;
sample.sections[0].role = "Customer Success Leader (fictional)";
sample.sections[0].headshot = sample.contributors.people[0].headshot;
["Morgan Ellis", "Taylor Morgan", "Alex Rivera", "Jamie Patel"].forEach((name, index) => {
  sample.contributors.people[index].name = name;
  sample.contributors.people[index].alt = `Illustrated mock portrait for ${name}, a fictional contributor`;
});
sample.contributors.body = "Meet the fictional editorial team behind this sample edition. These original JPEG illustrations show where your real contributors' approved headshots will appear.";
sample.footer.body += "\n\nThis is a public design demonstration, not an official Microsoft communication. All names, customer scenarios, quotes, and metrics are illustrative. The example.com contact below is a placeholder.";
const html = render(sample);
fs.writeFileSync(path.join(__dirname, "sample.html"), html, "utf8");
console.log(`Built complete sample.html: ${sample.sections.length} sections, ${sample.contributors.people.length} JPEG portraits, ${(Buffer.byteLength(html) / 1024).toFixed(1)} KB.`);
