import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..");

function parseArgs(argv) {
  const parsed = {
    output: path.join(repoRoot, "data", "pocketcasts-starred.json"),
    url: "https://pocketcasts.com/starred",
    limit: 200,
    headless: true,
    userDataDir: path.join(process.env.LOCALAPPDATA || process.env.TEMP || ".", "PocketCastsSync", "profile"),
    allowEmpty: false
  };
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    if (arg === "--output" && next) {
      parsed.output = path.resolve(next);
      i += 1;
    } else if (arg === "--url" && next) {
      parsed.url = next;
      i += 1;
    } else if (arg === "--limit" && next) {
      parsed.limit = Number.parseInt(next, 10) || parsed.limit;
      i += 1;
    } else if (arg === "--headed") {
      parsed.headless = false;
    } else if (arg === "--headless") {
      parsed.headless = true;
    } else if (arg === "--user-data-dir" && next) {
      parsed.userDataDir = path.resolve(next);
      i += 1;
    } else if (arg === "--allow-empty") {
      parsed.allowEmpty = true;
    }
  }
  return parsed;
}

async function ensureDir(filePath) {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
}

function formatDisplayDate(date) {
  return new Intl.DateTimeFormat("en-US", {
    year: "numeric",
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
    timeZoneName: "short"
  }).format(date);
}

async function launchContext(userDataDir, headless) {
  try {
    return await chromium.launchPersistentContext(userDataDir, {
      channel: "msedge",
      headless,
      viewport: { width: 1600, height: 1200 }
    });
  } catch {
    return chromium.launchPersistentContext(userDataDir, {
      headless,
      viewport: { width: 1600, height: 1200 }
    });
  }
}

async function scrapeStarred(options) {
  const context = await launchContext(options.userDataDir, options.headless);
  const page = context.pages()[0] || await context.newPage();
  await page.goto(options.url, { waitUntil: "domcontentloaded", timeout: 90_000 });
  await page.waitForTimeout(1500);
  const onLoginPage = await page.evaluate(() => {
    const url = window.location.href;
    if (url.includes("/user/login")) return true;
    const passwordField = document.querySelector('input[type="password"]');
    const submit = Array.from(document.querySelectorAll("button, [role='button']"))
      .map(el => (el.textContent || "").trim().toLowerCase())
      .some(text => text === "sign in" || text === "log in" || text === "login");
    return Boolean(passwordField && submit);
  });

  if (onLoginPage) {
    await context.close();
    throw new Error("Pocket Casts login is required. Run once with --headed, sign in, then rerun.");
  }

  const countVisibleItems = () => {
    const main = document.querySelector("main") || document.body;
    const selectors = [
      '[data-testid*="episode"]',
      '[class*="episode"]',
      '[class*="Episode"]',
      '[role="listitem"]',
      "li"
    ];
    const seen = new Set();
    let count = 0;
    for (const selector of selectors) {
      for (const node of main.querySelectorAll(selector)) {
        if (seen.has(node)) continue;
        seen.add(node);
        const text = (node.textContent || "").trim();
        if (text.length < 20) continue;
        if (!node.querySelector("a")) continue;
        count += 1;
      }
    }
    return count;
  };

  let lastCount = 0;
  let stableRounds = 0;
  for (let round = 0; round < 18; round += 1) {
    const currentCount = await page.evaluate(countVisibleItems);
    if (currentCount <= lastCount) {
      stableRounds += 1;
    } else {
      stableRounds = 0;
      lastCount = currentCount;
    }
    if (stableRounds >= 3) break;
    await page.mouse.wheel(0, 5000);
    await page.waitForTimeout(1000);
  }

  const items = await page.evaluate((limit) => {
    const main = document.querySelector("main") || document.body;
    const selectors = [
      '[data-testid*="episode"]',
      '[class*="episode"]',
      '[class*="Episode"]',
      '[role="listitem"]',
      "li"
    ];
    const titleSelectors = [
      '[data-testid*="title"]',
      '[class*="title"]',
      "h1", "h2", "h3", "h4",
      "a[title]",
      "strong"
    ];
    const subtitleSelectors = [
      '[data-testid*="podcast"]',
      '[class*="podcast"]',
      '[class*="show"]',
      '[class*="subtitle"]'
    ];

    const linesOf = text => text.split("\n").map(line => line.trim()).filter(Boolean);
    const getText = (root, choices) => {
      for (const choice of choices) {
        const node = root.querySelector(choice);
        if (!node) continue;
        const text = (node.textContent || "").trim();
        if (text) return text;
      }
      return "";
    };
    const parseDateLike = text => {
      const dateRegex = /\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2}\b/i;
      const relRegex = /\b(?:today|yesterday)\b/i;
      return (text.match(dateRegex)?.[0] || text.match(relRegex)?.[0] || "").trim();
    };
    const parseDuration = text => {
      const m = text.match(/\b\d+\s*(?:sec|secs|min|mins|hr|hrs|hour|hours)\b/i);
      return (m?.[0] || "").trim();
    };

    const seenRows = new Set();
    const out = [];

    for (const selector of selectors) {
      for (const row of main.querySelectorAll(selector)) {
        if (seenRows.has(row)) continue;
        seenRows.add(row);
        const fullText = (row.textContent || "").replace(/\s+/g, " ").trim();
        if (fullText.length < 20) continue;
        const anchors = Array.from(row.querySelectorAll("a[href]"));
        if (!anchors.length) continue;

        const titleFromSelector = getText(row, titleSelectors);
        const lineCandidates = linesOf(row.textContent || "");
        const title = titleFromSelector || lineCandidates.find(line => line.length > 6) || "";
        if (!title || /^starred$/i.test(title)) continue;

        const subtitle = getText(row, subtitleSelectors);
        const podcast =
          subtitle ||
          lineCandidates.find(line => line !== title && !/\d+\s*(?:sec|min|hr|hour)/i.test(line) && line.length > 2) ||
          "";

        const urls = anchors
          .map(anchor => anchor.href)
          .filter(Boolean)
          .filter(href => !href.includes("/starred") && !href.includes("/user/login"));
        const episodeUrl = urls.find(href => href.includes("pca.st") || href.includes("/podcast/") || href.includes("/episode/")) || urls[0] || "";
        const publishedLabel = parseDateLike(fullText);
        const duration = parseDuration(fullText);

        out.push({
          title,
          podcast,
          publishedLabel,
          duration,
          episodeUrl
        });
        if (out.length >= limit) break;
      }
      if (out.length >= limit) break;
    }

    const deduped = [];
    const seenKeys = new Set();
    for (const item of out) {
      const key = `${item.title.toLowerCase()}|${(item.podcast || "").toLowerCase()}`;
      if (seenKeys.has(key)) continue;
      seenKeys.add(key);
      deduped.push(item);
    }
    return deduped;
  }, options.limit);

  await context.close();
  return items;
}

async function main() {
  const options = parseArgs(process.argv);
  const now = new Date();
  const items = await scrapeStarred(options);
  if (!items.length && !options.allowEmpty) {
    throw new Error("No starred episodes were found. This usually means the session is signed out or selectors changed.");
  }

  const payload = {
    source: "Pocket Casts Starred",
    generatedAt: now.toISOString(),
    generatedDisplay: formatDisplayDate(now),
    profileUrl: options.url,
    publicUrl: "pocketcasts-starred.html",
    total: items.length,
    items
  };

  await ensureDir(options.output);
  await fs.writeFile(options.output, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
  process.stdout.write(`Saved ${items.length} starred episodes to ${options.output}\n`);
}

main().catch(error => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
