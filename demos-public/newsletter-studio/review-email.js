(function (root) {
  "use strict";
  const M = typeof module !== "undefined" && module.exports ? require("./review-model.js") : root.ReviewModel;
  const esc = (typeof module !== "undefined" && module.exports ? require("./email.js") : root.NewsletterEmail).escapeHtml;
  const font = "'Segoe UI',-apple-system,BlinkMacSystemFont,Arial,sans-serif";
  const text = value => esc(value).replace(/\r?\n/g, "<br>");
  const table = content => `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%;border-collapse:collapse;">${content}</table>`;
  const paragraphHtml = (html, extra = "") => `<p style="margin:0 0 10px 0;font-family:${font};font-size:14px;line-height:21px;color:#43516A;overflow-wrap:anywhere;word-wrap:break-word;${extra}">${html}</p>`;
  const p = (value, extra = "") => paragraphHtml(text(value), extra);
  function date(value) {
    return M.validDate(value) ? new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", year: "numeric", timeZone: "UTC" }).format(new Date(`${value}T00:00:00Z`)) : "Date to confirm";
  }
  function link(url, label) {
    const safe = M.safeUrl(url);
    return safe ? `<a href="${esc(safe)}" style="color:#006BB8;text-decoration:underline;overflow-wrap:anywhere;word-wrap:break-word;">${text(label)}</a>` : text(label || "Link needed");
  }
  function section(id, title, body, extra = "") {
    return `<tr><td id="${id}" data-review-section="${id}" class="section-pad" bgcolor="#FFFFFF" style="padding:22px 28px;background-color:#FFFFFF;border-bottom:1px solid #E3E9F1;${extra}"><h2 style="margin:0 0 13px 0;font-family:${font};font-size:18px;line-height:24px;font-weight:700;color:#263951;">${title}</h2>${body}</td></tr>`;
  }
  function dataTable(caption, headers, rows, widths) {
    return `<table class="data-table" aria-label="${esc(caption)}" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%;table-layout:fixed;border-collapse:collapse;font-family:${font};font-size:13px;line-height:19px;color:#43516A;"><thead><tr>${headers.map((h, i) => `<th scope="col" width="${widths[i]}%" bgcolor="#EDF2F8" style="width:${widths[i]}%;padding:9px 10px;background-color:#EDF2F8;border-bottom:2px solid #CAD7E7;text-align:left;font-size:11px;line-height:16px;letter-spacing:.4px;color:#304866;">${esc(h)}</th>`).join("")}</tr></thead><tbody>${rows.map((cells, index) => `<tr>${cells.map((cell, i) => `<${i === 0 ? 'th scope="row"' : "td"} valign="top" bgcolor="${index % 2 ? "#F7F9FC" : "#FFFFFF"}" style="padding:9px 10px;background-color:${index % 2 ? "#F7F9FC" : "#FFFFFF"};border-bottom:1px solid #E2E9F2;text-align:left;font-weight:${i === 0 ? "600" : "400"};overflow-wrap:anywhere;word-wrap:break-word;">${cell}</${i === 0 ? "th" : "td"}>`).join("")}</tr>`).join("")}</tbody></table>`;
  }
  function header(state) {
    const h = state.header;
    const urgent = M.sortRows(state.actions.required).find(row => M.validDate(row.date));
    const label = urgent && M.validDate(h.issueDate) && urgent.date < h.issueDate ? "OVERDUE AS OF THIS ISSUE" : "NEXT REQUIRED";
    const teasers = h.teasers.map(teaser => `<li style="margin:0 0 6px 0;padding-left:2px;font-size:13px;line-height:20px;color:#DCE8FF;">${M.sections.some(s => s.id === teaser.target && s.id !== "header") && M.present(state, teaser.target) ? `<a href="#${esc(teaser.target)}" style="color:#FFFFFF;text-decoration:underline;">${text(teaser.text)}</a>` : text(teaser.text)}</li>`).join("");
    return `<tr><td id="header" data-review-section="header" bgcolor="#163B68" style="background-color:#163B68;border-top:5px solid #0078D4;">
<!--[if mso]><v:rect fill="true" stroke="false" style="width:640px;"><v:fill type="gradient" color="#163B68" color2="#5B2C87" angle="0"/><v:textbox inset="0,0,0,0" style="mso-fit-shape-to-text:true;"><![endif]-->
${table(`<tr><td class="section-pad review-header" style="padding:22px 28px;background-image:linear-gradient(115deg,#163B68,#5B2C87);">${table(`<tr><td valign="middle" style="font-family:${font};font-size:10px;line-height:16px;letter-spacing:1.5px;color:#DCE8FF;">US SLED CSU<br>${text(h.edition)}</td><td width="138" align="right" style="width:138px;"><table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td class="logo-backing" bgcolor="#FFFFFF" style="padding:8px;background-color:#FFFFFF;"><img class="microsoft-logo" src="https://uhf.microsoft.com/images/microsoft/RE1Mu3b.png" alt="Microsoft" width="120" height="26" style="display:block;width:120px;height:26px;background-color:#FFFFFF;color:#737373;border:0;"></td></tr></table></td></tr>`)}<h1 style="margin:17px 0 14px 0;font-family:${font};font-size:31px;line-height:37px;font-weight:700;letter-spacing:-.5px;color:#FFFFFF;overflow-wrap:anywhere;">${text(h.name)}</h1><p style="margin:0 0 8px 0;font-family:${font};font-size:9px;line-height:14px;letter-spacing:1.7px;font-weight:700;color:#C5D8F5;">IN THIS ISSUE</p><ul style="margin:0;padding-left:17px;font-family:${font};">${teasers}</ul></td></tr>`)}
<!--[if mso]></v:textbox></v:rect><![endif]-->
</td></tr>${h.bannerUrl && M.safeUrl(h.bannerUrl) ? `<tr><td><img src="${esc(M.safeUrl(h.bannerUrl))}" alt="${esc(h.bannerAlt)}" width="640" height="120" style="display:block;width:100%;max-width:640px;height:auto;border:0;"></td></tr>` : ""}
${urgent ? `<tr><td class="section-pad urgent" bgcolor="#FFF1D8" style="padding:12px 28px;background-color:#FFF1D8;border-bottom:1px solid #F1D39C;font-family:${font};font-size:12px;line-height:19px;color:#674316;"><strong style="font-size:10px;letter-spacing:.7px;">${label}</strong><br><a href="#actions" style="color:#674316;text-decoration:underline;">${text(urgent.item)} &middot; ${date(urgent.date)}</a></td></tr>` : ""}
${h.notice.trim() ? `<tr><td class="section-pad" bgcolor="#F2F5F9" style="padding:9px 28px;background-color:#F2F5F9;font-family:${font};font-size:10px;line-height:15px;color:#617189;">${text(h.notice)}</td></tr>` : ""}`;
  }
  function render(state) {
    if (!M.validState(state)) throw new Error("Cannot render an invalid review draft.");
    const rows = [];
    rows.push(header(state));
    rows.push(section("scoreboard", "Scoreboard", p(`${state.scoreboard.period} · As of ${date(state.scoreboard.asOf)}`, "font-size:11px;line-height:17px;color:#73829A;") +
      (state.scoreboard.rows.length ? dataTable("Scoreboard", ["Metric", "Result", "Rank / YoY"], state.scoreboard.rows.map(row => [text(row.metric), `<strong style="color:#1266A5;">${text(row.result)}</strong>`, text(row.rank || "—")]), [42, 23, 35]) : p("No KPIs entered. Add a metric before exporting."))));
    if (M.present(state, "lead")) {
      const lead = state.lead;
      rows.push(section("lead", "Lead story", `<h3 style="margin:0 0 12px 0;font-family:${font};font-size:28px;line-height:34px;letter-spacing:-.5px;color:#203F62;overflow-wrap:anywhere;">${text(lead.title)}</h3>` +
        p(lead.summary, "font-size:17px;line-height:25px;font-weight:600;color:#245980;") +
        ["background", "win", "next"].map((key, i) => paragraphHtml(`<strong style="color:#273D5D;">${["Background", "The win", "What's next"][i]}.</strong> ${text(lead[key])}`)).join("") +
        p(`Team credit: ${lead.credit}`, "font-size:11px;line-height:17px;color:#728098;"), "border-top:3px solid #0078D4;"));
    }
    if (M.present(state, "leadership")) {
      const lead = state.leadership;
      const priorities = M.lines(lead.priorities);
      rows.push(section("leadership", "Leadership take", table(`<tr><td bgcolor="#F4F0F8" style="padding:15px 17px;background-color:#F4F0F8;border-left:3px solid #8050A1;">${p(`${lead.author} · ${lead.role}`, "font-size:12px;font-weight:700;color:#6D4889;")}${p(lead.body)}${priorities.length ? `<ul style="margin:8px 0 0 0;padding-left:18px;font-family:${font};font-size:13px;line-height:20px;color:#43516A;">${priorities.map(line => `<li style="margin-bottom:4px;">${text(line)}</li>`).join("")}</ul>` : ""}</td></tr>`)));
    }
    const required = M.sortRows(state.actions.required);
    const optional = M.sortRows(state.actions.optional);
    const subgroup = (title, body) => `<h3 style="margin:14px 0 8px 0;font-family:${font};font-size:13px;line-height:19px;color:#344A68;">${title}</h3>${body}`;
    rows.push(section("actions", "Deadlines &amp; action items",
      subgroup("Required by date", required.length ? dataTable("Required by date", ["Item", "Due date", "Access / Link"], required.map(row => [
        text(row.item), `${date(row.date)}${M.validDate(row.date) && M.validDate(state.header.issueDate) && row.date < state.header.issueDate ? '<br><strong style="color:#A84D23;">Overdue at issue date</strong>' : ""}`, link(row.url, row.label || "Open resource")
      ]), [40, 27, 33]) : p("No required deadlines listed for this issue.")) +
      subgroup("Optional / Recurring", optional.length ? dataTable("Optional / Recurring", ["Event", "Date / Time", "Location / Organizer"], optional.map(row => [
        row.url ? link(row.url, row.event) : text(row.event),
        `${date(row.date)}${row.time ? `<br>${text(row.time)} ${text(row.zone)}` : ""}${row.schedule ? `<br><span style="font-size:11px;">${text(row.schedule)}</span>` : ""}`,
        text(row.location)
      ]), [36, 32, 32]) : p("No optional or recurring events listed."))));
    if (M.present(state, "community")) {
      const community = state.community;
      rows.push(section("community", "Community", [
        community.welcome ? paragraphHtml(`<strong>Welcome:</strong> ${text(community.welcome)}`) : "",
        ...M.lines(community.awards).map(line => paragraphHtml(`<strong>Awards:</strong> ${text(line)}`)),
        community.social ? paragraphHtml(`<strong>Social:</strong> ${community.socialUrl ? link(community.socialUrl, community.social) : text(community.social)}`) : ""
      ].join("")));
    }
    const signoff = state.signoff;
    const people = signoff.portraitMode === "portraits" ? table(signoff.people.map(person => `<tr>${M.safeUrl(person.headshot) ? `<td width="52" valign="middle" style="width:52px;padding:5px 8px 5px 0;"><img src="${esc(M.safeUrl(person.headshot))}" alt="${esc(person.alt || person.name)}" width="44" height="44" style="display:block;width:44px;height:44px;border:0;border-radius:22px;"></td>` : '<td width="52" style="width:52px;"></td>'}<td valign="middle" style="padding:5px 0;font-family:${font};font-size:12px;line-height:18px;color:#43516A;">${text(person.name)} &middot; ${text(person.role)}</td></tr>`).join("")) : p(signoff.people.map(person => `${person.name} (${person.role})`).join(", "), "font-size:12px;line-height:19px;");
    rows.push(section("signoff", "Sign-off", p(`“${signoff.quote}”`, "font-family:Georgia,serif;font-size:20px;line-height:28px;font-style:italic;color:#67507D;") +
      p(`— ${signoff.attribution}`, "font-size:11px;line-height:17px;") + p("Contributors this issue", "margin-top:17px;font-size:10px;font-weight:700;letter-spacing:1px;text-transform:uppercase;") + people));
    return `<!doctype html>
<html lang="en" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><meta name="color-scheme" content="light dark"><meta name="supported-color-schemes" content="light dark"><meta name="format-detection" content="telephone=no,date=no,address=no,email=no"><title>${esc(state.header.name)} | ${esc(state.header.edition)}</title>
<!--[if mso]><xml><o:OfficeDocumentSettings><o:AllowPNG/><o:PixelsPerInch>96</o:PixelsPerInch></o:OfficeDocumentSettings></xml><![endif]-->
<style>body{margin:0;padding:0;-webkit-text-size-adjust:100%;}table,td,th{mso-table-lspace:0pt;mso-table-rspace:0pt;}table{border-spacing:0;}a[x-apple-data-detectors]{color:inherit!important;}
@media only screen and (max-width:600px){.section-pad{padding-left:18px!important;padding-right:18px!important;}.data-table td,.data-table th{padding:8px 6px!important;font-size:12px!important;line-height:18px!important;}.review-header h1{font-size:26px!important;line-height:32px!important;}}
@media(prefers-color-scheme:dark){body,.email-bg{background-color:#181E2A!important;}.email-container,td[bgcolor="#FFFFFF"],th[bgcolor="#FFFFFF"]{background-color:#222D3D!important;}td[bgcolor="#F7F9FC"],th[bgcolor="#F7F9FC"],th[bgcolor="#EDF2F8"],td[bgcolor="#F2F5F9"]{background-color:#2B384C!important;}td[bgcolor="#F4F0F8"]{background-color:#352D44!important;}p,h2,h3,.data-table,.data-table th,.data-table td{color:#DCE5F3!important;}strong{color:inherit!important;}a{color:#A9D5FF!important;}.review-header p,.review-header h1,.review-header a{color:#FFFFFF!important;}.urgent,.urgent a{color:#674316!important;}.logo-backing{background-color:#FFFFFF!important;}}</style>
</head><body style="margin:0;padding:0;background-color:#EDF1F6;font-family:${font};">
<table role="presentation" class="email-bg" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#EDF1F6" style="width:100%;background-color:#EDF1F6;border-collapse:collapse;"><tr><td align="center">
<!--[if mso]><table role="presentation" width="640" cellpadding="0" cellspacing="0" border="0"><tr><td><![endif]-->
<table role="presentation" class="email-container" width="640" cellpadding="0" cellspacing="0" border="0" bgcolor="#FFFFFF" style="width:100%;max-width:640px;table-layout:fixed;background-color:#FFFFFF;border-collapse:collapse;">${rows.join("\n")}</table>
<!--[if mso]></td></tr></table><![endif]-->
</td></tr></table></body></html>`;
  }
  const api = { render, formatDate: date };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.ReviewEmail = api;
})(typeof window !== "undefined" ? window : globalThis);
