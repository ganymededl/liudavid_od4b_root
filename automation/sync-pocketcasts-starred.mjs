import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import readline from "node:readline/promises";
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

function isTransientExecutionContextError(error) {
  const message = String(error?.message || error || "").toLowerCase();
  return (
    message.includes("execution context was destroyed") ||
    message.includes("cannot find context with specified id") ||
    message.includes("target closed") ||
    message.includes("most likely because of a navigation")
  );
}

function hasInteractiveConsole() {
  return Boolean(process.stdin?.isTTY && process.stdout?.isTTY);
}

async function acknowledgeAndContinue(message) {
  process.stdout.write(`${message}\n`);
  if (!hasInteractiveConsole()) {
    process.stdout.write("Non-interactive shell detected; continuing without acknowledgement prompt.\n");
    return;
  }

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });
  try {
    await rl.question("Press Enter to acknowledge and continue...");
  } finally {
    rl.close();
  }
}

async function evaluateWithNavigationRetry(page, fn, options) {
  const retries = options?.retries ?? 6;
  const delayMs = options?.delayMs ?? 300;
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    try {
      return await page.evaluate(fn);
    } catch (error) {
      if (!isTransientExecutionContextError(error) || attempt === retries) throw error;
      await page.waitForTimeout(delayMs);
    }
  }
  throw new Error("Failed to evaluate page state after navigation retries.");
}

async function isOnLoginPage(page) {
  return evaluateWithNavigationRetry(page, () => {
    const url = window.location.href;
    if (url.includes("/user/login")) return true;
    const passwordField = document.querySelector('input[type="password"]');
    const submit = Array.from(document.querySelectorAll("button, [role='button']"))
      .map(el => (el.textContent || "").trim().toLowerCase())
      .some(text => text === "sign in" || text === "log in" || text === "login");
    return Boolean(passwordField && submit);
  });
}

async function waitForManualLoginIfNeeded(page, options) {
  const initialLoginPage = await isOnLoginPage(page);
  if (!initialLoginPage) return;
  if (options.headless) {
    throw new Error("Pocket Casts login is required. Run once with --headed, sign in, then rerun.");
  }

  process.stdout.write("Pocket Casts sign-in required. Complete login in the opened browser window...\n");
  const start = Date.now();
  const timeoutMs = 10 * 60 * 1000;
  while (Date.now() - start < timeoutMs) {
    await page.waitForTimeout(2000);
    if (!(await isOnLoginPage(page))) {
      await page.goto(options.url, { waitUntil: "domcontentloaded", timeout: 90_000 });
      await page.waitForTimeout(1500);
      return;
    }
  }
  throw new Error("Timed out waiting for Pocket Casts sign-in in headed mode.");
}

async function isGoogleOAuthBlocked(page) {
  return evaluateWithNavigationRetry(page, () => {
    const bodyText = (document.body?.innerText || "").toLowerCase();
    const url = window.location.href.toLowerCase();
    return (
      url.includes("accounts.google.com") &&
      (bodyText.includes("couldn’t sign you in") ||
        bodyText.includes("couldn't sign you in")) &&
      bodyText.includes("this browser or app may not be secure")
    );
  });
}

async function waitForManualReadyConfirmation(page, options) {
  if (options.headless) return;
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });
  try {
    process.stdout.write(
      "When you can see your Pocket Casts Starred list in the opened browser, press Enter here to continue extraction...\n"
    );
    await rl.question("");
    await page.goto(options.url, { waitUntil: "domcontentloaded", timeout: 90_000 });
    await page.waitForTimeout(1500);
  } finally {
    rl.close();
  }
}

async function waitForStarredReady(page, options) {
  if (await isGoogleOAuthBlocked(page)) {
    throw new Error(
      "Google OAuth blocked this automated browser ('This browser or app may not be secure'). " +
      "Use Pocket Casts email/password login in this profile (not Google SSO), or pre-seed this profile with an already authenticated Pocket Casts session."
    );
  }
  const getState = () => {
    const bodyText = (document.body?.innerText || "").toLowerCase();
    const main = document.querySelector("main") || document.body;
    const hasStarredHeading = Array.from(document.querySelectorAll("h1, h2, [role='heading']"))
      .some(node => (node.textContent || "").trim().toLowerCase() === "starred");
    const challengeHints = [
      "captcha",
      "verify you are human",
      "checking your browser",
      "security check",
      "cloudflare"
    ];
    const hasChallenge = challengeHints.some(hint => bodyText.includes(hint));
    const emptyHints = [
      "no starred episodes",
      "you haven't starred",
      "you haven’t starred",
      "star episodes",
      "nothing here yet"
    ];
    const hasEmptyState = emptyHints.some(hint => bodyText.includes(hint));
    const candidateRows = main.querySelectorAll('[role="row"], tr, [role="listitem"], li, article, section, div');
    let episodeLikeRows = 0;
    for (const row of candidateRows) {
      const text = (row.textContent || "").replace(/\s+/g, " ").trim();
      if (text.length < 20) continue;
      const hasDuration = /\b\d+\s*(?:sec|secs|min|mins|hr|hrs|hour|hours)\b/i.test(text);
      const hasDateLike = /\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|today|yesterday)\b/i.test(text);
      if (hasDuration || hasDateLike) episodeLikeRows += 1;
      if (episodeLikeRows >= 3) break;
    }
    return { hasChallenge, hasStarredHeading, hasEmptyState, episodeLikeRows };
  };

  let state = await evaluateWithNavigationRetry(page, getState, { retries: 10, delayMs: 400 });
  if (state.hasStarredHeading && (state.episodeLikeRows > 0 || state.hasEmptyState)) return;
  if (options.headless && state.hasChallenge) {
    throw new Error("Pocket Casts returned a CAPTCHA/security challenge. Run with --headed and complete it in the browser.");
  }
  if (options.headless) return;

  process.stdout.write("Waiting for Pocket Casts Starred list to be ready (after CAPTCHA/sign-in)...\n");
  const start = Date.now();
  const timeoutMs = 12 * 60 * 1000;
  while (Date.now() - start < timeoutMs) {
    await page.waitForTimeout(2000);
    if (await isGoogleOAuthBlocked(page)) {
      throw new Error(
        "Google OAuth blocked this automated browser ('This browser or app may not be secure'). " +
        "Use Pocket Casts email/password login in this profile (not Google SSO), or pre-seed this profile with an already authenticated Pocket Casts session."
      );
    }
    state = await evaluateWithNavigationRetry(page, getState, { retries: 10, delayMs: 400 });
    if (state.hasStarredHeading && (state.episodeLikeRows > 0 || state.hasEmptyState)) return;
  }
  throw new Error("Timed out waiting for Pocket Casts Starred list after manual CAPTCHA/sign-in.");
}

function isRecoverableAuthError(error) {
  const message = String(error?.message || error || "").toLowerCase();
  return (
    message.includes("login is required") ||
    message.includes("captcha/security challenge") ||
    message.includes("google oauth blocked") ||
    message.includes("timed out waiting for pocket casts sign-in")
  );
}

async function runInteractiveAuthRecovery(options, reason) {
  const headedOptions = { ...options, headless: false };
  process.stdout.write(
    `Headless auth failed (${reason}). Launching browser so you can re-authenticate...\n`
  );

  const context = await launchContext(options.userDataDir, false);
  try {
    const page = context.pages()[0] || await context.newPage();
    await page.goto(options.url, { waitUntil: "domcontentloaded", timeout: 90_000 });
    await page.waitForTimeout(1500);
    await waitForManualLoginIfNeeded(page, headedOptions);
    await waitForManualReadyConfirmation(page, headedOptions);
    await waitForStarredReady(page, headedOptions);
    process.stdout.write("Pocket Casts authentication completed.\n");
    await acknowledgeAndContinue("Re-authentication acknowledged. Closing browser and resuming sync...");
  } finally {
    await context.close();
  }
}

async function scrapeStarred(options) {
  const context = await launchContext(options.userDataDir, options.headless);
  const page = context.pages()[0] || await context.newPage();
  await page.goto(options.url, { waitUntil: "domcontentloaded", timeout: 90_000 });
  await page.waitForTimeout(1500);
  await waitForManualLoginIfNeeded(page, options);
  await waitForManualReadyConfirmation(page, options);
  await waitForStarredReady(page, options);

  const countVisibleItems = () => {
    const main = document.querySelector("main") || document.body;
    const selectors = [
      '[role="row"]',
      "tr",
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
      '[role="row"]',
      "tr",
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
    const parseDuration = (lines, text) => {
      const exactLine = lines.find(line =>
        /^\d+\s*(?:sec|secs|min|mins|hr|hrs|hour|hours)$/i.test(line)
      );
      if (exactLine) return exactLine.trim();

      const mergedDateAndDuration = text.match(
        /\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+(\d{1,2})(\d{1,3})\s*(sec|secs|min|mins|hr|hrs|hour|hours)\b/i
      );
      if (mergedDateAndDuration) {
        const mergedValue = Number.parseInt(mergedDateAndDuration[2], 10);
        const unit = mergedDateAndDuration[3].toLowerCase();
        return `${mergedValue} ${unit}`;
      }

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

        const anchorCandidates = anchors.filter(anchor => {
          const href = anchor.href || "";
          return Boolean(href) && !href.includes("/starred") && !href.includes("/user/login");
        });
        if (anchorCandidates.length > 3) continue;

        const episodeAnchor =
          anchorCandidates.find(anchor =>
            anchor.href.includes("pca.st") ||
            anchor.href.includes("/podcast/") ||
            anchor.href.includes("/episode/")
          ) || anchorCandidates[0] || null;
        const episodeUrl = episodeAnchor?.href || "";

        const titleFromSelector = getText(row, titleSelectors);
        const titleFromAnchor = (episodeAnchor?.textContent || "").replace(/\s+/g, " ").trim();
        const lineCandidates = linesOf(row.textContent || "");
        const subtitle = getText(row, subtitleSelectors);
        const fallbackPodcast =
          lineCandidates.find(line => !/\d+\s*(?:sec|min|hr|hour)/i.test(line) && line.length > 2) || "";
        const podcast = subtitle || fallbackPodcast;

        let title = titleFromAnchor || titleFromSelector || lineCandidates.find(line => line.length > 6) || "";
        if (podcast) {
          const at = title.toLowerCase().indexOf(podcast.toLowerCase());
          if (at > 8) title = title.slice(0, at).trim();
        }
        title = title.replace(/\s+/g, " ").trim();
        if (!title || /^starred$/i.test(title)) continue;
        if (title.length > 180 && anchorCandidates.length > 1) continue;

        const hasDuration = /\b\d+\s*(?:sec|secs|min|mins|hr|hrs|hour|hours)\b/i.test(fullText);
        const hasDateLike = /\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|today|yesterday)\b/i.test(fullText);
        if (!hasDuration && !hasDateLike) continue;
        const publishedLabel = parseDateLike(fullText);
        const duration = parseDuration(lineCandidates, fullText);

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
    if (deduped.length) return deduped;

    // Fallback when Pocket Casts changes row markup: infer from visible text blocks.
    const coarse = [];
    const blocks = main.querySelectorAll("div, article, section, li, tr");
    for (const block of blocks) {
      const text = (block.textContent || "").replace(/\s+/g, " ").trim();
      if (text.length < 25) continue;
      const hasDuration = /\b\d+\s*(?:sec|secs|min|mins|hr|hrs|hour|hours)\b/i.test(text);
      const hasDateLike = /\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|today|yesterday)\b/i.test(text);
      if (!hasDuration && !hasDateLike) continue;
      const lines = linesOf(block.textContent || "");
      const title = lines.find(line => line.length > 10 && !/^starred$/i.test(line)) || "";
      if (!title) continue;
      const podcast = lines.find(line => line !== title && line.length > 2 && !/\b\d+\s*(?:sec|secs|min|mins|hr|hrs|hour|hours)\b/i.test(line)) || "";
      coarse.push({
        title,
        podcast,
        publishedLabel: parseDateLike(text),
        duration: parseDuration(text),
        episodeUrl: ""
      });
      if (coarse.length >= limit) break;
    }
    const fallbackDeduped = [];
    const fallbackSeen = new Set();
    for (const item of coarse) {
      const key = `${item.title.toLowerCase()}|${(item.podcast || "").toLowerCase()}`;
      if (fallbackSeen.has(key)) continue;
      fallbackSeen.add(key);
      fallbackDeduped.push(item);
    }
    return fallbackDeduped;
  }, options.limit);

  await context.close();
  return items;
}

async function main() {
  const options = parseArgs(process.argv);
  const now = new Date();

  let items;
  try {
    items = await scrapeStarred(options);
  } catch (error) {
    if (!options.headless || !isRecoverableAuthError(error)) throw error;
    await runInteractiveAuthRecovery(options, error.message || String(error));
    items = await scrapeStarred(options);
  }

  if (!items.length && !options.allowEmpty) {
    await acknowledgeAndContinue(
      "No starred episodes were found. This can be normal (empty Starred list) or indicate selector drift."
    );
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
