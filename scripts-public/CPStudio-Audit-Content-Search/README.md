# Copilot Studio Agent Conversation Export

Retrieves the **actual user prompts and agent responses** for Microsoft Copilot Studio agents
from the Microsoft Dataverse `conversationtranscript` table, and renders them as a filterable
HTML review report plus CSV and JSON evidence exports.

Two scripts:

| Script | Purpose |
|---|---|
| `Test-CopilotAuditReadiness.ps1` | **Run this first.** Surveys every environment in the tenant and tells you exactly what access you are missing, per environment. |
| `Export-CopilotStudioTranscripts.ps1` | Extracts the transcripts from an environment you can read. |

---

## Run this first

Copy and paste this whole block into **Windows PowerShell** (the built-in one is fine; PowerShell 7
also works). Replace only the tenant GUID.

```powershell
# 1. Go to the folder containing the scripts
cd C:\Scout_Output\CPStudio-Audit-Content-Search

# 2. Unblock them (only needed once, if the files came from email/download/Teams)
Unblock-File .\Test-CopilotAuditReadiness.ps1
Unblock-File .\Export-CopilotStudioTranscripts.ps1

# 3. READINESS SURVEY - can you actually read this data, in which environments?
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-CopilotAuditReadiness.ps1 `
    -TenantId <YOUR-TENANT-GUID>
```

A code appears in your console. Open **https://login.microsoft.com/device**, enter it, and sign in
as an admin **in that tenant**.

The survey prints a per-environment verdict and, for every environment marked `READY`, the exact
export command to run next. It also prints a remediation playbook for the ones that are blocked.

> **Why this step exists.** Being a Microsoft 365 Global Administrator does **not** grant access to
> this data. Microsoft documents that tenant admin roles do not automatically grant Dataverse data
> access, and that the Environment Maker role does not grant transcript access either. You need to
> be a Dataverse **user** in the environment *and* hold the **`Bot Transcript Viewer`** role there -
> separately, in **each** environment. There is no tenant-wide setting. Skipping this step is the
> most common reason an audit comes back empty.

Then run the export command the survey printed, or:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Export-CopilotStudioTranscripts.ps1 `
    -TenantId   <YOUR-TENANT-GUID> `
    -AuthMethod DeviceCode `
    -AllHistory -Format All -IncludeTraces
```

Open the HTML file it prints at the end. That is the deliverable.

### Readiness survey options

```powershell
# Also check Microsoft Purview role group membership (second sign-in prompt)
-CheckPurviewRoles

# Preview a self-grant of Bot Transcript Viewer without making it
-GrantSelfTranscriptViewer -WhatIf

# Actually grant it (needs System Administrator in that environment)
-GrantSelfTranscriptViewer

# Re-check a single environment after remediation
-EnvironmentUrl https://<org>.crm.dynamics.com

# Faster on large tenants: skip the per-environment retention probe
-SkipRetentionProbe
```

Read-only except for `-GrantSelfTranscriptViewer`, which supports `-WhatIf`.

### Where to get your tenant GUID

Any one of these:
- Entra admin center > **Overview** > Tenant ID
- Azure portal > Microsoft Entra ID > **Overview** > Tenant ID
- `https://login.microsoftonline.com/<yourdomain.com>/v2.0/.well-known/openid-configuration` - the
  GUID appears in the `issuer` value
- PowerShell, if Azure CLI is signed in to that tenant: `az account show --query tenantId -o tsv`

### If you get an execution policy error

The `-ExecutionPolicy Bypass` above already handles it. If you prefer to run the script directly
rather than through `powershell.exe`, set the policy for your user once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

---

## Why this exists

Microsoft Purview Audit and DSPM for AI reliably record that a Copilot Studio interaction
**happened** (user, time, source IP, host application, thread identifier). Getting the prompt and
response **body** out of them is conditional; getting it out of Dataverse is not.

| Question | Purview Audit | DSPM for AI | Dataverse transcripts |
|---|---|---|---|
| Did an interaction happen? | Yes | Yes | Yes |
| Who, when, from where? | Yes (incl. client IP) | Yes | Yes (no IP) |
| Which named agent? | Not reliably | Yes | Yes |
| **Actual prompt text** | No - `Messages` holds IDs and flags, not text | **Conditional** - see below | **Yes, unconditionally** |
| **Actual response text** | No | **Conditional** | **Yes, unconditionally** |
| Tool / MCP calls, errors | No | No | Yes |

### What "conditional" means

DSPM commonly reports *"Information not available - We couldn't retrieve this prompt and response."*
even for an administrator holding every relevant role. That is not a defect. **A role grants the
right to view content that exists; it does not cause Purview to capture anything.** Microsoft
documents these separate gates:

1. **Global Administrator is not sufficient** - the DSPM permissions table marks it as *not*
   permitted for viewing prompts and responses. You need `Content Explorer Content Viewer` or
   `Microsoft Purview Data Security AI Content Viewer`.
2. **The interacting user needs an Exchange Online mailbox** - *"When a user doesn't have a mailbox
   hosted in Exchange Online, no prompt or response is displayed."* Anonymous web-chat users never
   qualify.
3. **The collection policy must have Capture content enabled** - *"...no prompt or response is
   displayed if the option to capture content isn't selected in the policy."*
4. **Non-Microsoft channels require Purview pay-as-you-go billing** - demo site, custom website,
   Direct Line. Teams and M365 Copilot do not.
5. **Audit ingestion had to be on at the time** - enabling it later is never retroactive.
6. **Known issue** - *"The AI interaction event doesn't always display text... Sometimes, the prompt
   and response spans consecutive entries."*

Dataverse has none of these gates. It captures the moment transcript recording is on, which is the
default. **That is why this toolkit treats Dataverse as authoritative and Purview as corroboration.**

Copilot Studio content **is** mailbox-backed (`IPM.SkypeTeams.Message.Copilot.Studio.*`), so
eDiscovery can return it when capture succeeded - useful as a cross-check and for legal hold.

**Purview proves the interaction. Dataverse proves what was said.**

The join key between them is the Microsoft Entra ID object GUID:
Purview Audit `UserKey` / `UserId` == transcript turn `aadObjectId`.

---

## What you can and cannot recover

| | |
|---|---|
| **Default retention** | 30 days, enforced by the Dataverse job *"Bulk Delete Conversation Transcript Records Older Than 1 Month"*. **A default, not a platform limit** - an admin can extend it (Microsoft's own example uses 12 months). Measure it; never assume it. |
| **Never captured at all** | Microsoft 365 Copilot agents (declarative / Agent Builder), Dataverse for Teams environments, and **Developer environments**. No permission change will produce data for these. |
| **Partially captured** | SharePoint-grounded answers - the user's question is stored, but the generated answer is stored as `REDACTED`. |
| **Separate clock** | Copilot Studio's own session storage is a different store, retained up to 28 days, not configurable. Changing Dataverse retention does not change it. |
| **Per environment** | Every environment stores its own transcripts. There is no tenant-wide table. A complete tenant audit means one export per environment. |

Both scripts measure the real retention horizon in each environment and print it before you
interpret any export as complete.

---

## What `-Discover` gives you

**You do not need to know the Dataverse URL.** The script finds it via the Microsoft Global
Discovery Service using the signed-in identity, then reports what is recoverable. **One
interactive sign-in only** - the discovery token is silently exchanged for the environment token.

```
   DATAVERSE ENVIRONMENTS VISIBLE TO THIS IDENTITY
   FRIENDLY NAME                      URL NAME         ENVIRONMENT URL
   Contoso (default)                  orgd63eebeb      https://orgd63eebeb.crm.dynamics.com

[OK] Exactly one environment found; selected automatically
[OK] Reused existing sign-in (no second prompt).

   RETENTION HORIZON - what this environment can still produce
   Oldest transcript : 2026-08-11 03:04:37   (31 day(s) old)
   Newest transcript : 2026-09-10 14:33:44
   Times shown in    : Eastern Daylight Time
   Total transcripts : 44
   Recoverable span  : 30 day(s)

   Transcripts by agent (name as shown in the Agent Registry):
   AGENT                                    COUNT  OLDEST (EDT)          NEWEST (EDT)
   MCP Enterprise Admin Assistant              15  2026-08-15 14:45:53   2026-09-10 14:33:44
   MC Student Concierge                        12  2026-08-11 03:04:37   2026-09-08 03:21:17
   Harvard Writing Coach                        8  2026-08-31 15:34:35   2026-09-08 16:47:21
```

If several environments exist, they are all listed and you re-run with `-EnvironmentName`:

```powershell
# Just list them and stop
.\Export-CopilotStudioTranscripts.ps1 -TenantId <guid> -AuthMethod DeviceCode -ListEnvironments

# Then pick one by friendly name or URL name (partial match, case-insensitive)
.\Export-CopilotStudioTranscripts.ps1 -TenantId <guid> -AuthMethod DeviceCode `
    -EnvironmentName 'Contoso' -Discover
```

You can still pass `-EnvironmentUrl` explicitly at any time; discovery is skipped when you do.

---

## Scoping an export

| Need | Parameters |
|---|---|
| Environment URL unknown | omit `-EnvironmentUrl` - it is discovered automatically |
| List all reachable environments and stop | `-ListEnvironments` |
| Pick one of several environments | `-EnvironmentName 'Contoso'` |
| Everything retained | `-AllHistory` |
| Specific date range | `-StartDateUtc '2026-08-23' -EndDateUtc '2026-08-25'` |
| One agent | `-AgentName 'MCP Enterprise Admin Assistant'` |
| One user | `-User AdilE` |
| Different display time zone | `-TimeZoneId 'Pacific Standard Time'` |
| Oldest conversation first | `-SortOrder Oldest` |
| Combine any of the above | all filters are additive |
| See what would run, write nothing | `-WhatIf` |

Default window when nothing is specified: **last 90 days**.
Default display time zone: **Eastern Standard Time**. UTC is always retained alongside.
Default ordering: **conversations newest first**, and **turns oldest to newest within each
conversation** so an exchange always reads in the order it happened. Flip the conversation order
with `-SortOrder Oldest`, or use the **Newest first / Oldest first** selector in the HTML report
to re-order without re-running the export.

Server-side filtering is applied on the date range, so a large environment is never fully
downloaded unless you ask for it.

---

## You do not need to look up any IDs

The tool resolves friendly names to identifiers for you, using the Dataverse agent and user
directories that come with the **same token** already used to read transcripts. No Microsoft
Graph permissions and no extra consent.

### Agents - use the name from the Agent Registry

Copy the name exactly as it appears in **Microsoft 365 admin center > Copilot > Agents >
All agents**, for example `MCP Enterprise Admin Assistant`. You do not need the Entra agent ID.

```powershell
-AgentName 'MCP Enterprise Admin Assistant'   # friendly name from the registry
-AgentName 'Enterprise Admin'                  # partial name also works
-AgentName 'cr834_MCPEnterpriseAdminAssistant' # Dataverse schema name also works
```

Matching is case-insensitive and ignores spaces, underscores and hyphens.

> This matters because transcripts store the Dataverse **schema** name, which is often
> unrecognisable. For example `cr834_harvardprofessionalwritingc_3_SZtu` is the agent shown in
> the registry as **Harvard Writing Coach**. The report displays the friendly name and shows the
> schema name alongside for traceability.

### Users - use whatever you have

```powershell
-User AdilE                                    # alias
-User AdilE@contoso.onmicrosoft.com            # user principal name
-User 'Adil Eli'                               # display name (partial works)
-User 24ecf3bc-3a28-4657-bac1-b569df000107     # Entra object GUID
```

The match is confirmed before the export runs, so you can see who was selected:

```
[OK] User filter resolved: 'admin' -> MOD Administrator (admin@contoso.onmicrosoft.com)
     object ID cb410005-38ba-4475-bb3c-81b70678a246
```

If the value is ambiguous, every candidate is listed with name, UPN and object ID and the run
stops rather than guessing.

> The Entra object GUID is on the user's Entra profile under **Properties > Identity > Object ID**,
> and is the same value that appears as `UserKey` in a Purview Audit `CopilotInteraction` record.
> That is what makes an audit-to-content pivot a single command.

### Discovery lists both for you

`-Discover` prints every agent by its registry name with its own date range, and reminds you of
the `-AgentName` and `-User` syntax:

```
   Transcripts by agent (name as shown in the Agent Registry):
   AGENT                                    COUNT  OLDEST (EDT)          NEWEST (EDT)
   MCP Enterprise Admin Assistant              15  2026-08-15 14:45:53   2026-09-10 14:33:44
   MC Student Concierge                        12  2026-08-11 03:04:37   2026-09-08 03:21:17
   Harvard Writing Coach                        8  2026-08-31 15:34:35   2026-09-08 16:47:21
```

---

## Time zones

All human-readable timestamps default to **Eastern Standard Time** (shown as EDT or EST as
appropriate). Change with `-TimeZoneId`:

```powershell
-TimeZoneId 'Pacific Standard Time'
-TimeZoneId 'GMT Standard Time'
-TimeZoneId 'UTC'
```

UTC is always preserved in the JSON and CSV, and every HTML timestamp carries the UTC value as a
tooltip, so evidence integrity is never lost to a display preference.

---

## HTML report filters

The generated report is interactive and needs no re-run to slice further:

| Control | Behaviour |
|---|---|
| Free-text search | Matches prompt text, response text, agent name, conversation ID, user name and UPN |
| Agent dropdown | Friendly agent names as shown in the Agent Registry |
| User dropdown | Shows `Display Name - UPN`, not raw GUIDs |
| Date from / Date to | Filters by conversation start date in the display time zone |
| Conversation flag | `Had agent errors` / `Has user turns` |
| Expand all text | Expands every truncated long prompt |
| Reset filters | Returns to the full set |

Each turn is labelled with the real speaker - the user's display name and the agent's registry
name - rather than generic "User" and "Agent". Hovering a timestamp shows the UTC value.

Summary cards show conversations, total turns, agents, distinct users, conversations that used
knowledge sources, and conversations that hit agent errors.

---

## Output files

Written to `-OutputFolder` (default `C:\Scout_Output\CopilotStudio-Transcripts`):

| File | Purpose |
|---|---|
| `CopilotStudio-Transcripts-<stamp>.html` | Filterable chat-style review report - hand this to a stakeholder |
| `CopilotStudio-Transcripts-<stamp>.json` | **Verbatim** original text plus orchestration traces - evidence and chain of custody |
| `CopilotStudio-Turns-<stamp>.csv` | One row per turn, markup stripped, with `Excerpt` and `CharCount` - filtering and pivoting |
| `Export-Log-<stamp>.txt` | Full run log including the retention horizon and token identity |

Long machine-generated prompts (for example a full HTML email pasted into an autonomous trigger)
are shown in the HTML as readable excerpts with a **Show full text** control. The untouched
original is always preserved in the JSON.

---

## Authentication

| Option | Command | When |
|---|---|---|
| **Device code (recommended)** | `-TenantId <guid> -AuthMethod DeviceCode` | Any cross-tenant environment. Prompts once in the browser; **leaves your existing Azure CLI context untouched**. No app registration. |
| Azure CLI | `-AuthMethod AzureCli` | You are already signed in to the same tenant as the environment. |
| Supplied token | `-AccessToken <jwt> -AuthMethod Token` | Automation and pipelines. |

Before querying, the tool decodes the token and prints what it actually represents:

```
[OK   ] Token identity  : admin@contoso.onmicrosoft.com
[INFO ] Token tenant    : c1fdbce8-e6b0-43e2-82b5-6fbe5dda28b4
[INFO ] Token audience  : https://orgd63eebeb.crm.dynamics.com
```

Confirm those three lines match the target environment before trusting any output.

---

## Requirements

- Windows PowerShell 5.1 or PowerShell 7.x
- A Dataverse security role with **Read** on the `ConversationTranscript` table
- Read on the `Bot` and `SystemUser` tables for friendly-name resolution (included in most roles;
  without them the tool still runs and shows raw schema names and GUIDs)
- Azure CLI (only if using `-AuthMethod AzureCli`)
- Copilot Studio transcript recording **enabled** for the environment
- The agent must live in a **standard Dataverse environment**

---

## Known product limitations

- Transcripts are **not written** for Microsoft Dataverse for Teams environments or for
  Microsoft 365 Copilot agents.
- The recoverable window is governed by the environment's **Dataverse bulk deletion job**.
  The default job removes transcripts after roughly one month. Anything past that horizon is
  gone and cannot be recovered by any tool.
- Copilot Studio's own Monitor download covers only roughly the last 28 days and truncates each
  agent response to 512 characters. This tool reads Dataverse directly and has neither limit.
- Records larger than 1 MB are split across rows sharing the same `Name`. The tool merges them
  automatically in `Metadata.BatchId` order and logs each merge.
- SharePoint-grounded answers are omitted from transcripts and marked `REDACTED` by the product.

---

## Safety

- **Read-only** against Dataverse. It never modifies or deletes transcript records.
- Supports `-WhatIf`. The only writes are the local output files.
- Retries with exponential backoff on HTTP 429/5xx.
- **Turn integrity check**: aborts rather than writing a truncated export if every conversation
  reports exactly one turn, which would indicate a parsing defect rather than real data.
- Output contains full conversation text. Treat as sensitive and apply your organization's
  retention, privacy and least-privilege controls.

---

## Full documentation

```powershell
.\Export-CopilotStudioTranscripts.ps1 -Help
```

See `RUNBOOK.md` for the step-by-step administrator procedure, correlation guidance, and
troubleshooting.
