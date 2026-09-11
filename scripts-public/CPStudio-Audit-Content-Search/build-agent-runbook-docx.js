/*
 * Builds the Copilot Agent Audit administrator runbook as a Word document, then a PDF,
 * from RUNBOOK.md - matching the house style of CopilotChat-Compliance-Admin-OnePager.docx.
 *
 * Style rules taken from that document:
 *   - Title in caps, centred, dark blue
 *   - Centred blue subtitle and a small grey context line
 *   - Purpose callout: pale blue block with a blue left rule
 *   - "## " headings render as numbered blue section headings
 *   - "### " headings render as smaller blue sub-headings
 *   - Fenced code renders as Consolas on a pale blue-grey block
 *   - Tables get a blue header row and bold first column
 *   - Screenshots are centred with an italic grey caption
 *   - Blockquotes become callouts: amber for warnings, blue for notes, red for limitations
 */

const fs = require("fs");
const path = require("path");

/* The 'docx' package is not installed beside this script. Look in the usual
   places so this folder can be moved without breaking the build. */
function loadDocx() {
  const candidates = [
    path.join(__dirname, "node_modules", "docx"),
    path.join(__dirname, "..", "node_modules", "docx"),
    "C:\\Scout_Output\\Example-Docx-Build\\node_modules\\docx",
    "docx",
  ];
  for (const c of candidates) {
    try { return require(c); } catch (e) { /* try the next candidate */ }
  }
  console.error("ERROR: cannot locate the 'docx' package. Looked in:");
  candidates.forEach(c => console.error("  " + c));
  console.error("Fix with:  npm install docx     (run inside " + __dirname + ")");
  process.exit(1);
}

const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  WidthType, ImageRun, AlignmentType, BorderStyle, ShadingType, HeadingLevel,
  TableOfContents, PageBreak, Header, Footer, PageNumber, ExternalHyperlink,
} = loadDocx();

/* Everything resolves against this script's own folder, so RUNBOOK.md,
   Screenshots\ and this script can be relocated as a unit. */
const ROOT     = __dirname;
const SRC      = path.join(ROOT, "RUNBOOK.md");
const SHOTDIR  = path.join(ROOT, "Screenshots");
const OUTFILE  = path.join(ROOT, "Copilot-Agent-Audit-Administrator-Runbook.docx");

if (!fs.existsSync(SRC)) {
  console.error("ERROR: RUNBOOK.md not found at " + SRC);
  console.error("Keep RUNBOOK.md, the Screenshots folder and this script together.");
  process.exit(1);
}
if (!fs.existsSync(SHOTDIR)) {
  console.error("WARNING: no Screenshots folder at " + SHOTDIR);
  console.error("         Images will render as [missing image] placeholders.");
}

const BLUE      = "0F6CBD";
const DARKBLUE  = "10508F";
const INK       = "1F2933";
const MUTED     = "66717B";
const CODEBG    = "EEF2F6";
const NOTEBG    = "EAF3FB";
const WARNBG    = "FDF6E3";
const REDBG     = "FDF2F1";
const HDRBG     = "F2F5F8";

function pngSize(file) {
  const b = fs.readFileSync(file);
  return { width: b.readUInt32BE(16), height: b.readUInt32BE(20) };
}

/* Inline markdown -> (TextRun | ExternalHyperlink)[]. Handles **bold**, *italic*,
   `code`, [label](url) and bare URLs, keeping links clickable in Word and PDF. */
function runs(text, base = {}) {
  const out = [];
  const re = /(\[[^\]]+\]\(https?:\/\/[^)\s]+\)|<?https?:\/\/[^\s)\]>,]+>?|\*\*[^*]+\*\*|`[^`]+`|\*[^*\n]+\*)/g;
  let last = 0, m;
  const push = (t, extra) => {
    if (!t) return;
    out.push(new TextRun({ text: t, size: 21, color: INK, ...base, ...extra }));
  };
  const link = (label, url) => {
    linksEmbedded++;
    out.push(new ExternalHyperlink({
      link: url,
      children: [new TextRun({ text: label, size: 21, color: "0563C1", underline: {}, ...base })],
    }));
  };
  while ((m = re.exec(text)) !== null) {
    push(clean(text.slice(last, m.index)));
    const tok = m[0];
    const md = tok.match(/^\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)$/);
    if (md) link(clean(md[1]), md[2]);
    else if (/^<?https?:\/\//.test(tok)) {
      const url = tok.replace(/^</, "").replace(/>$/, "").replace(/[.,;:]$/, "");
      link(url, url);
    }
    else if (tok.startsWith("**")) push(clean(tok.slice(2, -2)), { bold: true });
    else if (tok.startsWith("`")) push(tok.slice(1, -1), { font: "Consolas", size: 19, color: "A33A2E" });
    else push(clean(tok.slice(1, -1)), { italics: true });
    last = m.index + tok.length;
  }
  push(clean(text.slice(last)));
  return out.length ? out : [new TextRun({ text: "", size: 21 })];
}

/* Turn [label](url) into "label", drop stray markdown artefacts. */
function clean(t) {
  return t
    .replace(/!\[([^\]]*)\]\([^)]+\)/g, "$1")
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, "$1")
    .replace(/&nbsp;/g, " ");
}

function para(text, opts = {}) {
  return new Paragraph({
    children: runs(text, opts.runOpts || {}),
    spacing: { after: opts.after ?? 110, before: opts.before ?? 0 },
    alignment: opts.align,
    indent: opts.indent,
    shading: opts.shading,
    border: opts.border,
    bullet: opts.bullet,
  });
}

function heading(text, level) {
  const sizes = { 1: 30, 2: 26, 3: 21 };
  return new Paragraph({
    children: [new TextRun({
      text: clean(text).replace(/`/g, ""), bold: true,
      size: sizes[level] || 21,
      color: level === 1 ? DARKBLUE : BLUE,
      font: "Segoe UI",
    })],
    spacing: { before: level === 1 ? 340 : 260, after: level === 1 ? 140 : 110 },
    heading: level === 1 ? HeadingLevel.HEADING_1
           : level === 2 ? HeadingLevel.HEADING_2 : HeadingLevel.HEADING_3,
    border: level === 1
      ? { bottom: { style: BorderStyle.SINGLE, size: 6, color: "D8DEE4", space: 4 } }
      : undefined,
  });
}

function codeBlock(lines) {
  return lines.map((l, i) => new Paragraph({
    children: [new TextRun({ text: l || " ", font: "Consolas", size: 17, color: "1F2933" })],
    spacing: { after: i === lines.length - 1 ? 130 : 0, before: i === 0 ? 40 : 0 },
    shading: { type: ShadingType.CLEAR, fill: CODEBG },
    indent: { left: 220, right: 220 },
  }));
}

/* Blockquote -> coloured callout. Tone is inferred from the leading words. */
function callout(lines) {
  const joined = lines.join(" ");
  let fill = NOTEBG, bar = BLUE;
  if (/limitation|do not|does not|never|cannot|refus|warning|critical|trap/i.test(joined)) { fill = REDBG; bar = "C0392B"; }
  else if (/known blocker|caution|note that|important|expect/i.test(joined)) { fill = WARNBG; bar = "E0B64A"; }
  return lines.map((l, i) => new Paragraph({
    children: runs(l),
    spacing: { after: i === lines.length - 1 ? 140 : 40, before: i === 0 ? 60 : 0 },
    shading: { type: ShadingType.CLEAR, fill },
    border: { left: { style: BorderStyle.SINGLE, size: 18, color: bar, space: 10 } },
    indent: { left: 220, right: 180 },
  }));
}

function cell(text, opts = {}) {
  return new TableCell({
    children: [new Paragraph({
      children: runs(text, opts.bold ? { bold: true } : {}),
      spacing: { after: 40, before: 40 },
    })],
    shading: opts.header ? { type: ShadingType.CLEAR, fill: HDRBG } : undefined,
    margins: { top: 70, bottom: 70, left: 110, right: 110 },
  });
}

function buildTable(rows) {
  const header = rows[0];
  const body = rows.slice(1);
  return new Table({
    width: { size: 100, type: WidthType.PERCENTAGE },
    rows: [
      new TableRow({
        tableHeader: true,
        children: header.map(h => cell(h, { header: true, bold: true })),
      }),
      ...body.map(r => new TableRow({
        children: r.map((c, i) => cell(c, { bold: i === 0 && r.length === 2 })),
      })),
    ],
  });
}

function image(src, alt) {
  const full = path.isAbsolute(src) ? src : path.join(ROOT, src.replace(/\//g, "\\"));
  if (!fs.existsSync(full)) {
    return [para(`[missing image: ${alt}]`, { runOpts: { color: "C0392B", italics: true } })];
  }
  const { width, height } = pngSize(full);
  const maxW = 600;
  const w = Math.min(width, maxW);
  const h = Math.round(height * (w / width));
  return [
    new Paragraph({
      children: [new ImageRun({ type: "png", data: fs.readFileSync(full), transformation: { width: w, height: h } })],
      alignment: AlignmentType.CENTER,
      spacing: { before: 160, after: 60 },
    }),
    new Paragraph({
      children: [new TextRun({ text: clean(alt), italics: true, size: 18, color: MUTED })],
      alignment: AlignmentType.CENTER,
      spacing: { after: 180 },
    }),
  ];
}

/* ------------------------------------------------------------------ parse */
const md = fs.readFileSync(SRC, "utf8").replace(/^\uFEFF/, "").split(/\r?\n/);
const children = [];
let docTitle = "Copilot Studio Agent Interaction Audit";
let i = 0, sectionNo = 0, subNo = 0, imagesEmbedded = 0, tablesBuilt = 0, linksEmbedded = 0;

/* Cover block, matching the one-pager. */
children.push(new Paragraph({
  children: [new TextRun({ text: "COPILOT STUDIO AGENT INTERACTION AUDIT", bold: true, size: 38, color: DARKBLUE, font: "Segoe UI" })],
  alignment: AlignmentType.CENTER, spacing: { before: 200, after: 60 },
}));
children.push(new Paragraph({
  children: [new TextRun({ text: "Administrator runbook", bold: true, size: 26, color: BLUE, font: "Segoe UI" })],
  alignment: AlignmentType.CENTER, spacing: { after: 60 },
}));
children.push(new Paragraph({
  children: [new TextRun({ text: "Copilot Studio custom agents | Microsoft 365 first-party agents | Dataverse, Purview eDiscovery and DSPM | Eastern Time", size: 17, color: MUTED })],
  alignment: AlignmentType.CENTER, spacing: { after: 240 },
}));
children.push(...callout([
  "**Purpose:** retrieve the actual user prompts and agent responses for Microsoft Copilot Studio custom agents and for Microsoft 365 first-party agents such as the Microsoft 365 Admin agent, and produce a report that management and compliance can review.",
]));
children.push(new Paragraph({
  children: [new TextRun({ text: "Contents", bold: true, size: 26, color: DARKBLUE, font: "Segoe UI" })],
  spacing: { before: 300, after: 120 },
}));
children.push(new TableOfContents("Contents", { hyperlinks: true, headingStyleRange: "1-3" }));
children.push(new Paragraph({ children: [new PageBreak()] }));

while (i < md.length) {
  const line = md[i];

  /* fenced code */
  if (/^\s*```/.test(line)) {
    const buf = [];
    i++;
    while (i < md.length && !/^\s*```/.test(md[i])) { buf.push(md[i]); i++; }
    i++;
    children.push(...codeBlock(buf));
    continue;
  }

  /* image on its own line */
  const img = line.match(/^\s*!\[([^\]]*)\]\(([^)]+)\)\s*$/);
  if (img) {
    children.push(...image(img[2], img[1]));
    imagesEmbedded++;
    i++;
    continue;
  }

  /* headings */
  const h = line.match(/^(#{1,6})\s+(.*)$/);
  if (h) {
    const lvl = h[1].length;
    // The source numbering is inconsistent (0.3 as a top-level, a 6A, no 7),
    // so strip it and renumber cleanly.
    let text = h[2].trim().replace(/^\d+[A-Za-z]*(?:\.\d+)*\.?\s+/, "");
    if (lvl === 1) { docTitle = text; i++; continue; }      // cover already carries the title
    if (lvl === 2) {
      sectionNo++; subNo = 0;
      children.push(heading(`${sectionNo}. ${text}`, 1));
    } else if (lvl === 3) {
      subNo++;
      children.push(heading(`${sectionNo}.${subNo} ${text}`, 2));
    } else {
      children.push(heading(text, 3));
    }
    i++;
    continue;
  }

  /* table */
  if (/^\s*\|.*\|\s*$/.test(line)) {
    const rows = [];
    while (i < md.length && /^\s*\|.*\|\s*$/.test(md[i])) {
      const cells = md[i].trim().replace(/^\||\|$/g, "").split("|").map(c => c.trim());
      if (!cells.every(c => /^:?-{2,}:?$/.test(c))) rows.push(cells);
      i++;
    }
    if (rows.length) {
      const width = Math.max(...rows.map(r => r.length));
      children.push(buildTable(rows.map(r => { while (r.length < width) r.push(""); return r; })));
      children.push(new Paragraph({ text: "", spacing: { after: 140 } }));
      tablesBuilt++;
    }
    continue;
  }

  /* blockquote */
  if (/^\s*>/.test(line)) {
    const buf = [];
    while (i < md.length && /^\s*>/.test(md[i])) {
      buf.push(md[i].replace(/^\s*>\s?/, ""));
      i++;
    }
    children.push(...callout(buf.filter(x => x.trim())));
    continue;
  }

  /* horizontal rule */
  if (/^\s*---+\s*$/.test(line)) { i++; continue; }

  /* list item */
  const li = line.match(/^\s*(?:[-*+]|\d+\.)\s+(.*)$/);
  if (li) {
    children.push(para(li[1], { bullet: { level: 0 }, after: 60 }));
    i++;
    continue;
  }

  /* blank */
  if (!line.trim()) { i++; continue; }

  /* paragraph - join wrapped lines */
  const buf = [line];
  i++;
  while (i < md.length && md[i].trim() &&
         !/^\s*(#{1,6}\s|\||>|```|---+\s*$|[-*+]\s|\d+\.\s|!\[)/.test(md[i])) {
    buf.push(md[i]); i++;
  }
  children.push(para(buf.join(" ")));
}

/* ------------------------------------------------------------------ build */
const doc = new Document({
  creator: "David Shih Chun Liu",
  title: "Copilot Studio Agent Interaction Audit - Administrator Runbook",
  description: "Retrieving prompts and responses for Copilot Studio custom agents and Microsoft 365 first-party agents.",
  styles: {
    default: {
      document: { run: { font: "Segoe UI", size: 21, color: INK }, paragraph: { spacing: { line: 276 } } },
    },
  },
  sections: [{
    properties: { page: { margin: { top: 900, bottom: 900, left: 1000, right: 1000 } } },
    headers: {
      default: new Header({
        children: [new Paragraph({
          children: [new TextRun({ text: "Copilot Studio Agent Interaction Audit - Administrator Runbook", size: 16, color: MUTED })],
          alignment: AlignmentType.RIGHT,
        })],
      }),
    },
    footers: {
      default: new Footer({
        children: [new Paragraph({
          children: [new TextRun({ children: ["Page ", PageNumber.CURRENT, " of ", PageNumber.TOTAL_PAGES], size: 16, color: MUTED })],
          alignment: AlignmentType.CENTER,
        })],
      }),
    },
    children,
  }],
});

Packer.toBuffer(doc).then(buf => {
  fs.writeFileSync(OUTFILE, buf);
  console.log("DOCX written : " + OUTFILE);
  console.log("Size         : " + Math.round(buf.length / 1024) + " KB");
  console.log("Sections     : " + sectionNo);
  console.log("Tables       : " + tablesBuilt);
  console.log("Screenshots  : " + imagesEmbedded);
  console.log("Hyperlinks   : " + linksEmbedded);
  console.log("Paragraphs   : " + children.length);
});
