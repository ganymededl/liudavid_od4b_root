"use strict";

(() => {
  const roles = window.SHOWCASE_ROLES;
  const $ = id => document.getElementById(id);
  const state = { role: roles.find(role => role.id === "research-admin"), prompt: 1, focus: "compare" };
  let toastTimer;
  let previousFocus;
  let renderedRole;
  const currentPrompt = () => state.role.prompts.find(prompt => prompt.id === state.prompt);
  const routeFor = (role, prompt) => `#/role/${role}/prompt/${prompt}`;
  const element = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  };

  function notify(message) {
    clearTimeout(toastTimer);
    $("toast").textContent = message;
    $("toast").classList.add("show");
    toastTimer = setTimeout(() => $("toast").classList.remove("show"), 4500);
  }

  async function copy(text, success) {
    try {
      if (!navigator.clipboard) throw new Error("Clipboard API is not available in this browser context.");
      await navigator.clipboard.writeText(text);
      notify(success);
    } catch (error) {
      console.warn("Clipboard write failed:", error);
      previousFocus = document.activeElement;
      $("dialog-title").textContent = "Copy manually";
      $("dialog-location").textContent = "Clipboard permission was unavailable";
      $("dialog-excerpt").replaceChildren();
      const field = element("textarea");
      field.value = text;
      field.readOnly = true;
      field.setAttribute("aria-label", "Text to copy manually");
      field.style.cssText = "width:100%;min-height:220px;background:var(--paper);color:var(--ink);font:inherit";
      $("dialog-excerpt").append(field);
      $("source-dialog").querySelector(".illustrative").textContent = "Manual clipboard fallback";
      $("source-dialog").querySelector("p:last-child").textContent = "Select the text and use your device's Copy command. Close this dialog when finished.";
      $("source-dialog").showModal();
      field.focus();
      field.select();
    }
  }

  for (const role of roles) {
    const link = element("a", "role-link");
    link.href = routeFor(role.id, 1);
    link.dataset.role = role.id;
    const icon = element("span", "role-icon", role.icon);
    icon.setAttribute("aria-hidden", "true");
    link.append(icon, element("span", "", role.name));
    $("role-nav").append(link);

    const label = element("label", "headcount-row");
    label.append(element("span", "", role.shortName));
    const input = element("input");
    Object.assign(input, { type: "number", id: `count-${role.id}`, name: role.id, min: "0", max: "10000", step: "1", value: "2", defaultValue: "2", required: true });
    input.setAttribute("aria-label", `${role.name} staff headcount`);
    label.append(input);
    $("headcounts").append(label);
  }

  function renderOutput(target, paragraphs, withCitations) {
    target.replaceChildren();
    for (const paragraph of paragraphs) {
      const section = element("section");
      section.append(element("h6", "", paragraph.heading));
      const body = element("p", "", paragraph.text);
      if (withCitations) {
        for (const citation of paragraph.cites) {
          const button = element("button", "citation", String(citation));
          button.setAttribute("aria-label", `Simulated source ${citation}: ${currentPrompt().sources[citation - 1].name}`);
          button.addEventListener("click", () => openSource(citation));
          body.append(document.createTextNode(" "), button);
        }
      }
      section.append(body);
      target.append(section);
    }
  }

  function render() {
    const prompt = currentPrompt();
    document.title = `${prompt.title} | Copilot Premium for Higher Ed — See the Difference`;
    $("role-title").textContent = state.role.name;
    $("role-description").textContent = state.role.description;
    for (const link of $("role-nav").children) {
      if (link.dataset.role === state.role.id) link.setAttribute("aria-current", "true");
      else link.removeAttribute("aria-current");
    }
    if (renderedRole !== state.role.id) {
      $("prompt-nav").replaceChildren();
      for (const task of state.role.prompts) {
        const link = element("a");
        link.href = routeFor(state.role.id, task.id);
        link.dataset.prompt = task.id;
        link.append(element("span", "", String(task.id).padStart(2, "0")), document.createTextNode(task.title));
        $("prompt-nav").append(link);
      }
      renderedRole = state.role.id;
    }
    for (const link of $("prompt-nav").children) {
      if (Number(link.dataset.prompt) === state.prompt) link.setAttribute("aria-current", "page");
      else link.removeAttribute("aria-current");
    }
    $("task-counter").textContent = `Task ${String(prompt.id).padStart(2, "0")} / 03 · ${prompt.tags.slice(0, 3).join(" / ")}`;
    $("task-title").textContent = prompt.title;
    $("task-description").textContent = prompt.task;
    $("free-prompt").textContent = prompt.freePrompt;
    $("premium-prompt").textContent = prompt.premiumPrompt;
    $("friction").replaceChildren(...prompt.friction.map(text => element("p", "annotation", text)));
    $("enablers").replaceChildren(...prompt.enablers.map(text => element("p", "annotation", text)));
    renderOutput($("free-output"), prompt.freeOutput, false);
    renderOutput($("premium-output"), prompt.premiumOutput, true);
    $("source-list").replaceChildren(...prompt.sources.map(source => {
      const item = element("li");
      item.append(element("strong", "", source.name), element("span", "", `${source.location} · FICTIONAL`), element("p", "", source.excerpt));
      return item;
    }));
    $("source-summary").textContent = `${prompt.sources.length} simulated sources · inspect the evidence`;
    $("handoff").textContent = prompt.handoff;
    document.querySelector(".source-details").open = false;
    setFocus(state.focus, false);
  }

  function readRoute(initial = false) {
    if (!location.hash.startsWith("#/") && !initial) return;
    const [path, query = ""] = location.hash.split("?");
    const match = path.match(/^#\/role\/([a-z-]+)\/prompt\/([1-3])$/);
    const role = match && roles.find(item => item.id === match[1]);
    if (match && role) {
      state.role = role;
      state.prompt = Number(match[2]);
      const focus = new URLSearchParams(query).get("view");
      state.focus = ["included", "premium", "compare"].includes(focus) ? focus : "compare";
    } else if (location.hash.startsWith("#/")) {
      notify("That task link is not available. Showing research proposal readiness.");
      state.role = roles.find(item => item.id === "research-admin");
      state.prompt = 1;
      state.focus = "compare";
      history.replaceState(null, "", routeFor(state.role.id, state.prompt));
    }
    render();
    if (initial && match && role) requestAnimationFrame(() => $("scenario").scrollIntoView({ behavior: "instant", block: "start" }));
  }

  function setFocus(focus, persist = true) {
    state.focus = focus;
    $("comparison").className = `comparison focus-${focus}`;
    document.querySelectorAll("[data-focus]").forEach(button => button.setAttribute("aria-pressed", String(button.dataset.focus === focus)));
    document.querySelector(".segment-indicator").style.transform = `translateX(${["included", "compare", "premium"].indexOf(focus) * 100}%)`;
    if (persist) history.replaceState(null, "", `${routeFor(state.role.id, state.prompt)}${focus === "compare" ? "" : `?view=${focus}`}`);
  }

  const focusButtons = [...document.querySelectorAll("[data-focus]")];
  focusButtons.forEach((button, index) => {
    button.addEventListener("click", () => setFocus(button.dataset.focus));
    button.addEventListener("keydown", event => {
      let next;
      if (event.key === "ArrowRight") next = (index + 1) % focusButtons.length;
      if (event.key === "ArrowLeft") next = (index + focusButtons.length - 1) % focusButtons.length;
      if (event.key === "Home") next = 0;
      if (event.key === "End") next = focusButtons.length - 1;
      if (next !== undefined) {
        event.preventDefault();
        focusButtons[next].focus();
        setFocus(focusButtons[next].dataset.focus);
      }
    });
  });
  window.addEventListener("hashchange", () => readRoute());
  document.querySelectorAll("[data-copy]").forEach(button => button.addEventListener("click", () =>
    copy(button.dataset.copy === "included" ? currentPrompt().freePrompt : currentPrompt().premiumPrompt, `${button.dataset.copy === "included" ? "Included" : "Premium"} prompt copied.`)));
  $("copy-role").addEventListener("click", () => {
    const text = `${state.role.name}\nFictional training prompts. Replace sources with approved institutional context; never paste personal records without authorization.\n\n${state.role.prompts.map(prompt => `${prompt.id}. ${prompt.title}\n\nCOPILOT CHAT (INCLUDED)\n${prompt.freePrompt}\n\nCOPILOT PREMIUM\n${prompt.premiumPrompt}`).join("\n\n---\n\n")}`;
    copy(text, "All 3 prompt pairs copied (6 prompts).");
  });
  $("share-link").addEventListener("click", () => {
    const url = new URL(location.href);
    url.hash = `${routeFor(state.role.id, state.prompt)}${state.focus === "compare" ? "" : `?view=${state.focus}`}`;
    copy(url.href, "Link copied to this task and comparison view.");
  });

  function openSource(number) {
    const source = currentPrompt().sources[number - 1];
    previousFocus = document.activeElement;
    $("dialog-title").textContent = source.name;
    $("dialog-location").textContent = source.location;
    $("dialog-excerpt").textContent = source.excerpt;
    $("source-dialog").querySelector(".illustrative").textContent = "Fictional source · illustrative only";
    $("source-dialog").querySelector("p:last-child").textContent = "This is a simulated citation, not a live SharePoint file or Teams record. In a real workflow, open the original source, check its date and authority, and verify the claim.";
    $("source-dialog").showModal();
    $("close-dialog").focus();
  }
  $("close-dialog").addEventListener("click", () => $("source-dialog").close());
  $("source-dialog").addEventListener("close", () => previousFocus?.focus());

  function search() {
    const raw = $("search").value.trim();
    const terms = raw.toLocaleLowerCase().split(/\s+/).filter(Boolean);
    $("clear-search").hidden = !raw;
    $("search-results").hidden = !raw;
    $("search-results").replaceChildren();
    if (!raw) {
      $("search-count").textContent = "";
      return;
    }
    const matches = roles.flatMap(role => role.prompts.map(prompt => ({ role, prompt }))).filter(({ role, prompt }) => {
      const content = `${role.name} ${prompt.title} ${prompt.task} ${prompt.tags.join(" ")} ${prompt.freePrompt} ${prompt.premiumPrompt} ${prompt.sources.map(source => source.excerpt).join(" ")}`.toLocaleLowerCase();
      return terms.every(term => content.includes(term));
    });
    $("search-count").textContent = `${matches.length} of 18 tasks`;
    if (!matches.length) $("search-results").append(element("p", "", "No matching tasks. Try grants, enrollment, permissions, or alumni."));
    for (const { role, prompt } of matches) {
      const link = element("a");
      link.href = routeFor(role.id, prompt.id);
      link.append(element("strong", "", prompt.title), element("span", "", role.shortName));
      link.addEventListener("click", () => {
        $("search").value = "";
        search();
        state.role = role;
        state.prompt = prompt.id;
        state.focus = "compare";
        render();
        requestAnimationFrame(() => {
          $("task-title").tabIndex = -1;
          $("task-title").focus({ preventScroll: true });
          $("scenario").scrollIntoView({ block: "start" });
        });
      });
      $("search-results").append(link);
    }
  }
  $("search").addEventListener("input", search);
  $("clear-search").addEventListener("click", () => { $("search").value = ""; search(); $("search").focus(); });
  $("search").addEventListener("keydown", event => {
    if (event.key === "Escape") { $("search").value = ""; search(); }
  });

  const money = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });
  const priceMoney = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const number = new Intl.NumberFormat("en-US", { maximumFractionDigits: 1 });
  const resultIds = ["annual-hours", "gross-value", "license-cost", "net-value", "payback", "benefit-ratio"];
  function calculate() {
    $("rate-label").value = `${$("realization").value}%`;
    const inputs = [...$("roi-form").querySelectorAll("input")];
    const invalid = inputs.filter(input => !input.validity.valid || !Number.isFinite(input.valueAsNumber));
    inputs.forEach(input => input.setAttribute("aria-invalid", String(invalid.includes(input))));
    if (invalid.length) {
      $("calc-error").textContent = "Enter a value in every field within its allowed range. Headcounts and working weeks must be whole numbers; task hours use half-hour increments.";
      resultIds.forEach(id => { $(id).value = "—"; delete $(id).dataset.raw; });
      $("seat-count").textContent = "Inputs need attention";
      $("formula-text").textContent = "Correct the highlighted inputs to calculate an estimate.";
      $("payback-note").textContent = "No estimate is shown while inputs are invalid.";
      return;
    }
    $("calc-error").textContent = "";
    const seats = roles.reduce((total, role) => total + $(`count-${role.id}`).valueAsNumber, 0);
    const hours = $("hours").valueAsNumber;
    const hourly = $("hourly-cost").valueAsNumber;
    const price = $("seat-price").valueAsNumber;
    const weeks = $("weeks").valueAsNumber;
    const rate = $("realization").valueAsNumber / 100;
    const recovered = seats * hours * weeks * rate;
    const gross = recovered * hourly;
    const cost = seats * price * 12;
    const net = gross - cost;
    for (const [id, value, formatted] of [
      ["annual-hours", recovered, number.format(recovered)], ["gross-value", gross, money.format(gross)],
      ["license-cost", cost, money.format(cost)], ["net-value", net, money.format(net)]
    ]) { $(id).value = formatted; $(id).dataset.raw = value; }
    $("seat-count").textContent = `${number.format(seats)} ${seats === 1 ? "seat" : "seats"}`;
    let payback;
    if (seats === 0) {
      payback = "No seats";
      $("payback-note").textContent = "Add staff headcount to model a pilot.";
    } else if (cost === 0) {
      payback = "No license cost";
      $("payback-note").textContent = "At a zero seat price, license-cost payback is not applicable; other implementation costs still exist.";
    } else if (gross === 0) {
      payback = "No payback";
      $("payback-note").textContent = "There is no modeled capacity value to offset license cost.";
    } else {
      const months = cost / (gross / 12);
      payback = months < 0.1 ? "<0.1 month" : `${number.format(months)} months`;
      $("payback-note").textContent = months > 12
        ? "Beyond the first year: annual capacity value is lower than annual license cost. Recurring licenses do not break even under these assumptions."
        : "The modeled annual capacity value covers annual licensing. This is not a guaranteed saving or a cash return.";
    }
    $("payback").value = payback;
    $("benefit-ratio").value = cost > 0 ? `${number.format(gross / cost)}×` : "Not applicable";
    $("formula-text").textContent = `${seats} staff × ${hours} task hours/week × ${weeks} weeks × ${Math.round(rate * 100)}% = ${number.format(recovered)} hours/year. Hours × ${money.format(hourly)}/hour = ${money.format(gross)} capacity value. ${seats} seats × ${priceMoney.format(price)}/month × 12 = ${money.format(cost)} annual licensing. Net capacity value = ${money.format(gross)} − ${money.format(cost)} = ${money.format(net)}. Display totals are rounded; no intermediate rounding is used.`;
  }
  $("roi-form").addEventListener("submit", event => event.preventDefault());
  $("roi-form").addEventListener("input", calculate);
  $("roi-form").addEventListener("reset", () => requestAnimationFrame(calculate));
  $("print").addEventListener("click", () => window.print());
  const printDetails = new Map();
  window.addEventListener("beforeprint", () => {
    document.querySelectorAll("details").forEach(detail => { printDetails.set(detail, detail.open); detail.open = true; });
  });
  window.addEventListener("afterprint", () => { printDetails.forEach((open, detail) => { detail.open = open; }); printDetails.clear(); });

  const systemTheme = matchMedia("(prefers-color-scheme: dark)");
  let explicitTheme = false;
  function applyTheme(dark) {
    document.documentElement.dataset.theme = dark ? "dark" : "light";
    $("theme-toggle").setAttribute("aria-pressed", String(dark));
    $("theme-toggle").setAttribute("aria-label", dark ? "Use light mode" : "Use dark mode");
  }
  let savedTheme;
  try { savedTheme = localStorage.getItem("higher-ed-theme"); }
  catch (error) { console.warn("Theme preference storage is unavailable; using the system theme.", error); }
  explicitTheme = savedTheme === "dark" || savedTheme === "light";
  applyTheme(explicitTheme ? savedTheme === "dark" : systemTheme.matches);
  $("theme-toggle").addEventListener("click", () => {
    explicitTheme = true;
    const dark = document.documentElement.dataset.theme !== "dark";
    applyTheme(dark);
    try { localStorage.setItem("higher-ed-theme", dark ? "dark" : "light"); }
    catch (error) { console.warn("Theme preference was not saved:", error); notify("Theme changed for this visit; browser storage is unavailable."); }
  });
  systemTheme.addEventListener("change", event => { if (!explicitTheme) applyTheme(event.matches); });
  readRoute(true);
  calculate();
})();
