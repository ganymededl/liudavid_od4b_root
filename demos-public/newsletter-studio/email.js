/* The email renderer is independent of the studio UI. All authored text is escaped. */
(function (root) {
  "use strict";

  const FONT = "'Segoe UI',-apple-system,BlinkMacSystemFont,Arial,sans-serif";
  const TYPES = {
    leadership: { label: "FROM THE DESK OF", color: "#5B2C87", tint: "#F4EFF9" },
    interview: { label: "IN CONVERSATION", color: "#5B2C87", tint: "#F4EFF9" },
    success: { label: "SUCCESS STORY", color: "#0078D4", tint: "#EBF5FD" },
    practice: { label: "BEST PRACTICE", color: "#177465", tint: "#EDF7F3" },
    tip: { label: "TIP OF THE MONTH", color: "#9A5914", tint: "#FFF5E6" }
  };

  function escapeHtml(value) {
    return String(value ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  }
  const lines = value => String(value || "").split(/\r?\n/).map(x => x.trim()).filter(Boolean);
  const text = value => escapeHtml(value).replace(/\r?\n/g, "<br>");
  const table = (content, extra = "") => `<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="width:100%;border-collapse:collapse;${extra}">${content}</table>`;
  const gap = (height = 18) => `<tr><td height="${height}" style="height:${height}px;font-size:1px;line-height:${height}px;">&nbsp;</td></tr>`;
  const paragraph = (value, color = "#536078") => String(value || "").trim().split(/\r?\n\s*\r?\n/).filter(Boolean).map(p => `<p style="margin:0 0 14px 0;font-family:${FONT};font-size:14px;line-height:23px;color:${color};overflow-wrap:anywhere;word-wrap:break-word;">${text(p)}</p>`).join("");
  const label = value => `<p style="margin:19px 0 7px 0;font-family:${FONT};font-size:11px;line-height:16px;font-weight:700;letter-spacing:1px;color:#283B58;">${escapeHtml(value)}</p>`;
  const list = (value, ordered = false) => {
    const items = lines(value);
    if (!items.length) return "";
    const tag = ordered ? "ol" : "ul";
    return `<${tag} style="margin:8px 0 16px 0;padding-left:22px;color:#536078;font-family:${FONT};font-size:14px;line-height:23px;">${items.map(item => `<li style="margin:0 0 7px 0;padding-left:3px;overflow-wrap:anywhere;word-wrap:break-word;">${text(item.replace(/^(?:[-*•]\s+|\d+[.)]\s+)/, ""))}</li>`).join("")}</${tag}>`;
  };
  function sectionAnchor(section, index) {
    return `section-${String(section.id || "item").replace(/[^a-zA-Z0-9_-]/g, "")}-${index}`;
  }
  function safeImage(value) {
    try {
      const url = new URL(String(value));
      return ["https:", "http:"].includes(url.protocol) ? escapeHtml(url.href) : "";
    } catch {
      return "";
    }
  }
  function quote(value, color = "#5B2C87") {
    if (!String(value || "").trim()) return "";
    return table(`<tr><td style="padding:18px 20px;border-left:3px solid ${color};background-color:#F6F3FA;" bgcolor="#F6F3FA"><p style="margin:0;font-family:Georgia,'Times New Roman',serif;font-size:22px;font-style:italic;line-height:31px;color:#53406F;overflow-wrap:anywhere;word-wrap:break-word;">&ldquo;${text(value)}&rdquo;</p></td></tr>`) + table(gap());
  }
  function stats(value) {
    const metrics = lines(value).slice(0, 4).map(line => {
      const [number, ...caption] = line.split("|");
      return { number: number.trim(), caption: caption.join("|").trim() };
    });
    if (!metrics.length) return "";
    const chunks = metrics.length === 4 ? [metrics.slice(0, 2), metrics.slice(2)] : [metrics];
    return table(chunks.map(chunk => `<tr>${chunk.map(metric => `<td class="stat-cell" width="${Math.floor(100 / chunk.length)}%" valign="top" style="width:${100 / chunk.length}%;padding:5px;">${table(`<tr><td bgcolor="#FFF4DF" style="background-color:#FFF4DF;border:1px solid #F6E6C5;border-radius:8px;padding:17px 12px;text-align:center;"><p style="margin:0;font-family:${FONT};font-size:26px;line-height:34px;font-weight:700;color:#9B5B13;overflow-wrap:anywhere;word-wrap:break-word;">${text(metric.number)}</p>${metric.caption ? `<p style="margin:4px 0 0 0;font-family:${FONT};font-size:10px;line-height:16px;color:#8B6A3C;">${text(metric.caption)}</p>` : ""}</td></tr>`)}</td>`).join("")}</tr>`).join("")) + table(gap(10));
  }
  function interviewExchanges(value) {
    const entries = [];
    for (const line of String(value || "").split(/\r?\n/)) {
      const match = line.match(/^\s*([QA]):\s*(.*)$/i);
      if (match) entries.push({ kind: match[1].toUpperCase(), body: match[2] });
      else if (entries.length) entries[entries.length - 1].body += "\n" + line;
      else if (line.trim()) entries.push({ kind: "A", body: line });
    }
    return entries.map(entry => table(`<tr><td class="qa-marker" width="31" valign="top" style="width:31px;padding-top:2px;font-family:${FONT};font-size:12px;line-height:22px;font-weight:700;color:${entry.kind === "Q" ? "#6C3B93" : "#0078D4"};">${entry.kind}.</td><td class="qa-copy" valign="top" style="padding-bottom:13px;font-family:${FONT};font-size:14px;line-height:23px;color:${entry.kind === "Q" ? "#293B56" : "#536078"};font-weight:${entry.kind === "Q" ? "600" : "400"};overflow-wrap:anywhere;word-wrap:break-word;">${text(entry.body.trim())}</td></tr>`)).join("");
  }
  function sectionBody(section) {
    switch (section.type) {
      case "leadership": {
        const image = safeImage(section.headshot);
        return table(`<tr>${image ? `<td width="80" valign="middle" style="width:80px;padding-bottom:20px;"><img src="${image}" alt="${escapeHtml(section.author || "Author headshot")}" width="64" height="64" style="display:block;width:64px;height:64px;border:0;border-radius:32px;color:#5B2C87;font-family:${FONT};font-size:11px;"></td>` : ""}<td valign="middle" style="padding-bottom:20px;"><p style="margin:0;font-family:${FONT};font-size:13px;line-height:20px;font-weight:700;color:#344360;">${text(section.author)}</p><p style="margin:3px 0 0 0;font-family:${FONT};font-size:11px;line-height:18px;color:#8891A3;">${text(section.role)}</p></td></tr>`) +
          paragraph(section.body) + (lines(section.highlights).length ? label("THIS MONTH’S FOCUS") + list(section.highlights) : "");
      }
      case "interview":
        return (section.series ? `<p style="margin:0 0 8px 0;font-family:${FONT};font-size:12px;line-height:20px;font-weight:600;color:#795397;">${text(section.series)}</p>` : "") +
          (section.byline ? `<p style="margin:0 0 20px 0;font-family:${FONT};font-size:11px;line-height:18px;color:#8891A3;">${text(section.byline)}</p>` : "") +
          paragraph(section.body) + interviewExchanges(section.exchanges) + quote(section.quote) +
          (section.closing ? `<p style="margin:5px 0 0 0;font-family:${FONT};font-size:12px;line-height:20px;font-style:italic;color:#795397;">${text(section.closing)}</p>` : "");
      case "success":
      case "practice":
        return `<p style="margin:0 0 6px 0;font-family:${FONT};font-size:12px;line-height:20px;font-weight:600;color:#344360;">${text(section.customer)}</p><p style="margin:0 0 19px 0;font-family:${FONT};font-size:11px;line-height:19px;color:#8891A3;">${text(section.team)}</p>` +
          (section.opportunity ? label("THE OPPORTUNITY") + paragraph(section.opportunity) : "") +
          (section.solution ? label("THE APPROACH") + paragraph(section.solution) : "") +
          (section.outcomes || section.stats ? label("THE IMPACT") + list(section.outcomes) + stats(section.stats) : "") + quote(section.quote) +
          (section.tip ? table(`<tr><td bgcolor="#F0F5FB" style="padding:16px 18px;background-color:#F0F5FB;border-left:3px solid #85B9DF;"><p style="margin:0 0 6px 0;font-family:${FONT};font-size:10px;line-height:16px;font-weight:700;letter-spacing:.7px;color:#2F668F;">TAKE IT TO YOUR CUSTOMER &rarr;</p><p style="margin:0;font-family:${FONT};font-size:13px;line-height:21px;color:#536078;overflow-wrap:anywhere;word-wrap:break-word;">${text(section.tip)}</p></td></tr>`) : "");
      case "tip":
        return paragraph(section.body) + list(section.items, section.listStyle === "numbered") +
          String(section.prompts || "").trim().split(/\r?\n\s*\r?\n/).filter(Boolean).map(prompt => table(`<tr><td bgcolor="#F7F4FC" style="background-color:#F7F4FC;padding:18px;border:1px solid #E8E1F0;border-radius:7px;"><p style="margin:0 0 8px 0;font-family:${FONT};font-size:9px;line-height:16px;letter-spacing:1px;font-weight:700;color:#81639C;">TRY THIS PROMPT</p><p style="margin:0;font-family:Consolas,'Courier New',monospace;font-size:12px;line-height:21px;color:#5F4B73;overflow-wrap:anywhere;word-wrap:break-word;">${text(prompt)}</p></td></tr>`) + table(gap(12))).join("");
      default:
        throw new Error(`Unknown section type: ${section.type}`);
    }
  }
  function renderSection(section, index) {
    const type = TYPES[section.type];
    if (!type) throw new Error(`Unknown section type: ${section.type}`);
    const card = section.type === "success" || section.type === "practice";
    const outlookStart = card ? '<!--[if mso]><v:roundrect arcsize="3%" strokecolor="#E2E9F2" strokeweight="1px" fillcolor="#FFFFFF" style="width:584px;"><v:textbox inset="0,0,0,0" style="mso-fit-shape-to-text:true;"><![endif]-->' : "";
    const outlookEnd = card ? '<!--[if mso]></v:textbox></v:roundrect><![endif]-->' : "";
    return `<tr><td class="outer-pad" style="padding:0 28px 24px 28px;"><a id="${sectionAnchor(section, index)}" name="${sectionAnchor(section, index)}"></a>${outlookStart}${table(`<tr><td class="card-pad${card ? " story-card" : ""}" bgcolor="#FFFFFF" style="background-color:#FFFFFF;padding:${card ? "26px" : "8px 6px 4px 6px"};${card ? "border:1px solid #E2E9F2;border-radius:12px;box-shadow:0 3px 12px #EAF0F6;" : ""}"><span style="display:inline-block;padding:5px 8px;background-color:${type.tint};color:${type.color};font-family:${FONT};font-size:9px;line-height:15px;font-weight:700;letter-spacing:1.3px;border-radius:4px;">${type.label}</span><h2 style="margin:13px 0 18px 0;font-family:${FONT};font-size:25px;line-height:33px;letter-spacing:-.5px;font-weight:700;color:#233752;overflow-wrap:anywhere;word-wrap:break-word;">${text(section.title || "Untitled section")}</h2>${sectionBody(section)}</td></tr>`)}${outlookEnd}</td></tr>`;
  }
  function microsoftLogo() {
    return `<table role="presentation" align="right" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;"><tr><td class="microsoft-logo-backplate" bgcolor="#FFFFFF" style="padding:10px 12px;background-color:#FFFFFF;border-radius:5px;"><img class="microsoft-logo" src="https://uhf.microsoft.com/images/microsoft/RE1Mu3b.png" alt="Microsoft" width="144" height="31" style="display:block;width:144px;height:31px;border:0;font-family:${FONT};font-size:22px;color:#737373;background-color:#FFFFFF;"></td></tr></table>`;
  }
  function renderMasthead(masthead) {
    const banner = renderBanner(masthead);
    // An auto-growing VML textbox avoids clipping longer newsletter names in Word.
    return `<tr><td bgcolor="#1269B0" style="background-color:#1269B0;background-image:linear-gradient(115deg,#0078D4 0%,#5B2C87 100%);">
<!--[if gte mso 9]><v:rect fill="true" stroke="false" style="width:640px;"><v:fill type="gradient" color="#0078D4" color2="#5B2C87" angle="0"/><v:textbox inset="0,0,0,0" style="mso-fit-shape-to-text:true;"><![endif]-->
${banner ? "" : table(`<tr><td align="right" style="padding:24px 38px 0 38px;">${microsoftLogo()}</td></tr>`)}
${table(`<tr><td class="masthead-pad" style="padding:34px 38px 36px 38px;"><p style="margin:0 0 22px 0;font-family:${FONT};font-size:10px;line-height:17px;letter-spacing:3px;font-weight:600;color:#DCEBFF;">US SLED CSU &nbsp; / &nbsp; THE MONTHLY EDIT</p><h1 style="margin:0 0 9px 0;font-family:${FONT};font-size:54px;line-height:64px;letter-spacing:2px;font-weight:750;color:#FFFFFF;overflow-wrap:anywhere;word-wrap:break-word;">${text(masthead.name)}</h1>${masthead.tagline ? `<p style="margin:0 0 25px 0;font-family:${FONT};font-size:14px;line-height:23px;color:#E1E5FF;">${text(masthead.tagline)}</p>` : ""}${table(`<tr><td style="border-top:1px solid #8CA8D6;padding-top:17px;"><p style="margin:0;font-family:${FONT};font-size:11px;line-height:19px;letter-spacing:2px;font-weight:600;color:#FFFFFF;">${text(masthead.edition)}</p></td><td width="96" align="right" valign="bottom" style="width:96px;padding-top:17px;font-family:${FONT};font-size:9px;line-height:19px;letter-spacing:1px;color:#DCEBFF;">IDEAS TO IMPACT</td></tr>`)}</td></tr>`)}
<!--[if gte mso 9]></v:textbox></v:rect><![endif]-->
</td></tr>${banner}`;
  }
  function renderBanner(masthead) {
    const source = safeImage(masthead.bannerUrl);
    if (masthead.bannerMode !== "photo" || !source) return "";
    const height = masthead.bannerShape === "cinematic" ? 320 : 240;
    return `<tr><td bgcolor="#172B48" style="background-color:#172B48;border-top:4px solid #EFB65B;"><img class="hero-photo" src="${source}" alt="${escapeHtml(masthead.bannerAlt || "Newsletter banner")}" width="640" height="${height}" style="display:block;width:100%;max-width:640px;height:auto;aspect-ratio:640/${height};object-fit:cover;border:0;font-family:${FONT};font-size:14px;line-height:22px;color:#FFFFFF;"></td></tr><tr><td class="outer-pad" bgcolor="#172B48" style="padding:16px 34px;background-color:#172B48;">${table(`<tr><td valign="middle" style="padding-right:14px;"><p style="margin:0;font-family:${FONT};font-size:10px;line-height:18px;letter-spacing:2px;font-weight:600;color:#F4D3A0;overflow-wrap:anywhere;">${text(masthead.bannerCaption)}</p></td><td width="168" align="right" valign="middle" style="width:168px;">${microsoftLogo()}</td></tr>`)}</td></tr>`;
  }
  function renderContributors(contributors) {
    if (!contributors?.people?.length) return "";
    const rows = [];
    for (let index = 0; index < contributors.people.length; index += 4) {
      const members = contributors.people.slice(index, index + 4);
      rows.push(`<tr>${members.map(person => {
        const source = safeImage(person.headshot);
        const initials = String(person.name || "?").trim().split(/\s+/).slice(0, 2).map(part => part[0] || "").join("");
        const portrait = source
          ? `<img src="${source}" alt="${escapeHtml(person.alt || `${person.name || "Contributor"} headshot`)}" width="88" height="88" style="display:block;width:88px;height:88px;border:3px solid #FFFFFF;border-radius:44px;object-fit:cover;font-family:${FONT};font-size:10px;color:#5B2C87;">`
          : `<table role="presentation" align="center" width="88" cellpadding="0" cellspacing="0" border="0"><tr><td width="88" height="88" align="center" bgcolor="#E5DDF0" style="width:88px;height:88px;background-color:#E5DDF0;border-radius:44px;font-family:${FONT};font-size:25px;font-weight:700;color:#5B2C87;">${escapeHtml(initials)}</td></tr></table>`;
        return `<td class="contributor-cell" width="25%" align="center" valign="top" style="width:25%;padding:16px 6px;text-align:center;">${table(`<tr><td align="center">${portrait}</td></tr><tr><td style="padding-top:12px;text-align:center;"><p style="margin:0 0 4px 0;font-family:${FONT};font-size:12px;line-height:18px;font-weight:700;color:#443158;overflow-wrap:anywhere;word-wrap:break-word;">${text(person.name)}</p><p style="margin:0;font-family:${FONT};font-size:10px;line-height:17px;color:#81718F;overflow-wrap:anywhere;word-wrap:break-word;">${text(person.role)}</p></td></tr>`)}</td>`;
      }).join("")}${Array.from({ length: 4 - members.length }, () => '<td class="contributor-empty" width="25%" style="width:25%;"></td>').join("")}</tr>`);
    }
    return `<tr><td id="contributors" class="outer-pad" bgcolor="#F6F3FA" style="padding:32px 28px 26px 28px;background-color:#F6F3FA;border-top:1px solid #E6DDEF;"><p style="margin:0 0 10px 0;font-family:${FONT};font-size:9px;line-height:16px;letter-spacing:2px;font-weight:700;color:#9274AC;">THE PEOPLE BEHIND THE IMPACT</p><h2 style="margin:0 0 10px 0;font-family:${FONT};font-size:26px;line-height:34px;letter-spacing:-.5px;color:#443158;">${text(contributors.title)}</h2>${paragraph(contributors.body, "#81718F")}${table(rows.join(""), "table-layout:fixed;")}</td></tr>`;
  }
  function renderToc(sections) {
    if (!sections.length) return "";
    return `<tr><td class="outer-pad" bgcolor="#F5F7FB" style="padding:24px 34px 22px 34px;background-color:#F5F7FB;border-bottom:1px solid #E8EDF5;"><p style="margin:0 0 13px 0;font-family:${FONT};font-size:9px;line-height:15px;font-weight:700;letter-spacing:2px;color:#8994AA;">IN THIS EDITION</p>${table(sections.map((section, index) => `<tr><td width="29" valign="top" style="width:29px;padding:5px 0;font-family:${FONT};font-size:10px;line-height:19px;color:#9684B2;">${String(index + 1).padStart(2, "0")}</td><td style="padding:5px 0;font-family:${FONT};font-size:12px;line-height:19px;"><a href="#${sectionAnchor(section, index)}" style="color:#405776;text-decoration:none;overflow-wrap:anywhere;word-wrap:break-word;">${text(section.title || "Untitled section")} <span style="color:#9DAFC5;">&rarr;</span></a></td></tr>`).join(""))}</td></tr>${gap(28)}`;
  }
  function emailAddress(value) {
    const address = String(value || "").trim();
    return /^[^\s@<>"?&]+@[^\s@<>"?&]+\.[^\s@<>"?&]+$/.test(address) ? address : "";
  }
  function renderFooter(footer) {
    const email = emailAddress(footer.email);
    const href = email ? escapeHtml(`mailto:${encodeURIComponent(email).replace(/%40/g, "@")}`) : "";
    return `<tr><td class="outer-pad" bgcolor="#ECEAF5" style="padding:33px 34px;background-color:#ECEAF5;border-top:3px solid #A38ABD;"><p style="margin:0 0 10px 0;font-family:${FONT};font-size:9px;line-height:16px;font-weight:700;letter-spacing:2px;color:#876D9F;">BETTER, TOGETHER</p><h2 style="margin:0 0 12px 0;font-family:${FONT};font-size:25px;line-height:33px;color:#443158;overflow-wrap:anywhere;word-wrap:break-word;">${text(footer.title)}</h2>${paragraph(footer.body, "#73637F")}${href ? `
${table(`<tr><td style="padding:5px 0 19px 0;">
<!--[if mso]><v:roundrect href="${href}" style="height:44px;v-text-anchor:middle;width:184px;" arcsize="15%" stroke="f" fillcolor="#5B2C87"><w:anchorlock/><center style="color:#FFFFFF;font-family:'Segoe UI',Arial,sans-serif;font-size:12px;font-weight:bold;">Share your feedback &#8594;</center></v:roundrect><![endif]-->
<!--[if !mso]><!--><a href="${href}" style="display:inline-block;background-color:#5B2C87;border:1px solid #5B2C87;border-radius:7px;padding:13px 21px;font-family:${FONT};font-size:12px;line-height:18px;font-weight:600;color:#FFFFFF;text-decoration:none;text-align:center;mso-hide:all;">Share your feedback &rarr;</a><!--<![endif]-->
</td></tr>`)}<p style="margin:0 0 20px 0;font-family:${FONT};font-size:11px;line-height:19px;color:#73637F;">${text(footer.contactName)}${footer.contactName ? " &middot; " : ""}<a href="${href}" style="color:#695082;text-decoration:underline;overflow-wrap:anywhere;word-wrap:break-word;">${escapeHtml(email)}</a></p>` : paragraph([footer.contactName, footer.email].filter(Boolean).join(" · "), "#73637F")}${footer.tagline ? `<p style="margin:0;padding-top:18px;border-top:1px solid #D9D2E5;font-family:${FONT};font-size:11px;line-height:19px;letter-spacing:.5px;font-weight:600;color:#7A638E;overflow-wrap:anywhere;word-wrap:break-word;">${text(footer.tagline)}</p>` : ""}</td></tr>`;
  }
  function render(state) {
    const sections = state.sections || [];
    return `<!doctype html>
<html lang="en" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:w="urn:schemas-microsoft-com:office:word" xmlns:o="urn:schemas-microsoft-com:office:office">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<meta name="format-detection" content="telephone=no,date=no,address=no,email=no">
<title>${escapeHtml(state.masthead.name)} | ${escapeHtml(state.masthead.edition)}</title>
<!--[if mso]><xml><o:OfficeDocumentSettings><o:AllowPNG/><o:PixelsPerInch>96</o:PixelsPerInch></o:OfficeDocumentSettings></xml><style>table,td{mso-table-lspace:0pt;mso-table-rspace:0pt;}a{text-decoration:none;}.story-card{border:0!important;background-color:transparent!important;}</style><![endif]-->
<style>
:root{color-scheme:light dark;supported-color-schemes:light dark;}
body{margin:0;padding:0;-webkit-text-size-adjust:100%;-ms-text-size-adjust:100%;}
table{border-spacing:0;}table,td{mso-table-lspace:0pt;mso-table-rspace:0pt;}img{-ms-interpolation-mode:bicubic;}
a[x-apple-data-detectors]{color:inherit!important;text-decoration:none!important;}
@media only screen and (max-width:600px){
.email-container{width:100%!important;}.outer-pad{padding-left:18px!important;padding-right:18px!important;}.card-pad{padding:20px!important;}
.masthead-pad{padding:28px 24px!important;}.masthead-pad h1{font-size:42px!important;line-height:51px!important;letter-spacing:1px!important;}
.stat-cell{display:block!important;width:auto!important;padding:5px 0!important;}
.contributor-cell{display:block!important;width:auto!important;padding:16px 0!important;}.contributor-empty{display:none!important;}
}
@media(prefers-color-scheme:dark){
body,.email-bg{background-color:#181D2A!important;}.email-container{background-color:#222A38!important;}
td[bgcolor="#FFFFFF"]{background-color:#222A38!important;}td[bgcolor="#F5F7FB"],td[bgcolor="#F0F5FB"]{background-color:#293449!important;}
td[bgcolor="#F6F3FA"],td[bgcolor="#F7F4FC"],td[bgcolor="#ECEAF5"]{background-color:#312A42!important;}
h2{color:#E8ECF5!important;}p,li,.qa-copy{color:#CDD5E5!important;}.qa-marker{color:#B99EE2!important;}td[bgcolor="#FFF4DF"] p{color:#875013!important;}
a{color:#BACFFF!important;}.masthead-pad p,.masthead-pad h1{color:#FFFFFF!important;}a[href^="mailto:"]{color:#FFFFFF!important;}
td.microsoft-logo-backplate{background-color:#FFFFFF!important;}
}
[data-ogsc] h2{color:#E8ECF5!important;}
</style>
</head>
<body style="margin:0;padding:0;background-color:#EDF0F6;font-family:${FONT};color:#536078;word-wrap:break-word;">
<div style="display:none;font-size:1px;line-height:1px;color:#EDF0F6;max-height:0;max-width:0;opacity:0;overflow:hidden;mso-hide:all;">${escapeHtml(state.masthead.edition)} — ${escapeHtml(state.masthead.tagline)}</div>
<table role="presentation" class="email-bg" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#EDF0F6" style="width:100%;background-color:#EDF0F6;border-collapse:collapse;"><tr><td align="center" valign="top">
<!--[if mso]><table role="presentation" width="640" cellpadding="0" cellspacing="0" border="0"><tr><td><![endif]-->
<table role="presentation" class="email-container" align="center" width="640" cellpadding="0" cellspacing="0" border="0" bgcolor="#FFFFFF" style="width:100%;max-width:640px;table-layout:fixed;background-color:#FFFFFF;border-collapse:collapse;">
${renderMasthead(state.masthead)}
${renderToc(sections)}
${sections.length ? sections.map(renderSection).join("\n") : gap(28)}
${renderContributors(state.contributors)}
${renderFooter(state.footer)}
</table>
<!--[if mso]></td></tr></table><![endif]-->
</td></tr></table>
</body>
</html>`;
  }
  const api = { render, escapeHtml, sectionAnchor, emailAddress, safeImage };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.NewsletterEmail = api;
})(typeof window !== "undefined" ? window : globalThis);
