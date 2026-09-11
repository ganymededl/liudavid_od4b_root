<#
.SYNOPSIS
    Renders an HTML conversation report for FIRST-PARTY Microsoft 365 Copilot agent interactions
    (Microsoft 365 Admin, Researcher, Analyst, Facilitator, and similar) from an eDiscovery PST export.

.DESCRIPTION
    THE WORKFLOW THIS COMPLETES

      1. Purview > Solutions > eDiscovery > Content Search > create a search with
             ItemClass:IPM.SkypeTeams.Message.Copilot* AND (Sent>=yyyy-MM-dd AND Sent<=yyyy-MM-dd)
         scoped to the INTERACTING user's mailbox. Get-FirstPartyAgentInteractions.ps1 automates this.
      2. Export that search and download it with the eDiscovery Export Tool.
      3. Point this script at the extracted folder. It produces the same style of readable
         conversation report that Export-CopilotStudioTranscripts.ps1 produces for custom agents.

    WHY A SEPARATE SCRIPT IS NEEDED

    First-party agents never write to the Dataverse conversationtranscript table, so the Copilot
    Studio exporter cannot see them. Their content lives in the interacting user's Exchange mailbox.
    Purview DSPM renders the user's prompt but has no Response field at all, so the mailbox export is
    the only way to recover what the agent actually said.

    HOW TURNS ARE PAIRED

    Copilot Chat labels its turns "**prompt N**" in the body. First-party AGENTS do not - they are
    paired by SENDER IDENTITY instead. The user's own address is the prompt; anything else (for
    example M365AdminAgent@teams.microsoft.com) is the agent response. That is what this script keys
    on, which is why it also works when a single export contains several different agents.

.PARAMETER ExportPath
    Extracted eDiscovery export folder. Searched recursively for *.pst and for exported HTML
    transcript files, so it works with either export format.

.PARAMETER PreferHtml
    Parse exported HTML transcripts even when PST files are also present. Useful when Outlook COM is
    unavailable or unreliable on the workstation.

.PARAMETER UserUpn
    The interacting user's address. Messages sent by this address are classified as prompts;
    everything else is classified as an agent response. If omitted, the script infers the most
    frequent human sender and reports what it chose.

.PARAMETER OutputFolder
    Folder for the HTML, CSV and JSON reports.

.PARAMETER StartUtc
    Inclusive UTC start. Defaults to 7 days before now.

.PARAMETER EndUtc
    Exclusive UTC end. Defaults to now.

.PARAMETER TimeZoneId
    Windows time zone for displayed timestamps. Defaults to Eastern Standard Time.
    UTC is always retained in the CSV and JSON for chain of custody.

.PARAMETER SortOrder
    Default conversation order: Newest (default) or Oldest. Turns inside a conversation are ALWAYS
    rendered oldest to newest. The HTML also has a live order selector.

.PARAMETER ConversationGapMinutes
    When the export carries no usable conversation identifier, turns separated by more than this
    many minutes start a new conversation. Defaults to 30.

.EXAMPLE
    .\Get-FirstPartyAgentReport.ps1 -ExportPath 'C:\Scout_Output\M365AdminExport' `
        -UserUpn 'admin@contoso.onmicrosoft.com'

.EXAMPLE
    .\Get-FirstPartyAgentReport.ps1 -ExportPath 'C:\Export' -SortOrder Oldest `
        -StartUtc ([datetime]'2026-09-10T00:00:00Z')

.NOTES
    Requires Outlook to be installed - the PST is read through the Outlook COM object, the same
    mechanism used by Get-CopilotChatComplianceReport.ps1.

    The script fails loudly rather than producing a metadata-only report. If no message body can be
    read it stops, because a report that lists timestamps without prompt or answer text is worse
    than no report - it looks like evidence and is not.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [Parameter(Mandatory = $true)]
    [string] $ExportPath,

    [Parameter(Mandatory = $false)]
    [string] $UserUpn,

    [Parameter(Mandatory = $false)]
    [string] $OutputFolder = 'C:\Scout_Output\FirstParty-Agent-Audit',

    [Parameter(Mandatory = $false)]
    [datetime] $StartUtc = (Get-Date).ToUniversalTime().AddDays(-7),

    [Parameter(Mandatory = $false)]
    [datetime] $EndUtc = (Get-Date).ToUniversalTime().AddDays(1),

    [Parameter(Mandatory = $false)]
    [string] $TimeZoneId = 'Eastern Standard Time',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Newest', 'Oldest')]
    [string] $SortOrder = 'Newest',

    [Parameter(Mandatory = $false)]
    [int] $ConversationGapMinutes = 30,

    [Parameter(Mandatory = $false)]
    [switch] $PreferHtml,

    [Parameter(Mandatory = $false)]
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string] $Message,
        [Parameter(Mandatory = $false)][ValidateSet('INFO','OK','WARN','ERROR','STEP')][string] $Level = 'INFO'
    )
    $line = "[{0}] [{1,-5}] {2}" -f (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'), $Level, $Message
    switch ($Level) {
        'OK'    { Write-Host $line -ForegroundColor Green }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'STEP'  { Write-Host $line -ForegroundColor Cyan }
        default { Write-Host $line -ForegroundColor Gray }
    }
}

if (-not $Force) {
    Write-Host ''
    Write-Host '  ===================================================================' -ForegroundColor Cyan
    Write-Host '   FIRST-PARTY COPILOT AGENT REPORT - from eDiscovery PST export' -ForegroundColor Cyan
    Write-Host '  ===================================================================' -ForegroundColor Cyan
    Write-Host '   Renders prompts AND agent responses as a readable conversation' -ForegroundColor White
    Write-Host '   report. Purview DSPM shows the prompt only - it has no Response' -ForegroundColor Gray
    Write-Host '   field for these agents at all.' -ForegroundColor Gray
    Write-Host ''
    Write-Host '   TYPICAL RUN' -ForegroundColor White
    Write-Host '     .\Get-FirstPartyAgentReport.ps1 -ExportPath <extracted export folder> `' -ForegroundColor Green
    Write-Host '         -UserUpn user@contoso.com' -ForegroundColor Green
    Write-Host ''
    Write-Host '   Requires Outlook installed (PSTs are read via Outlook COM).' -ForegroundColor DarkGray
    Write-Host '   Suppress this banner with -Force.' -ForegroundColor DarkGray
    Write-Host '  ===================================================================' -ForegroundColor Cyan
    Write-Host ''
}

if (-not (Test-Path -LiteralPath $ExportPath -PathType Container)) {
    Write-Log -Level 'ERROR' -Message "ExportPath does not exist or is not a folder: $ExportPath"
    return
}

try   { $displayZone = [TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId) }
catch {
    Write-Log -Level 'WARN' -Message ("Unknown time zone '{0}'; falling back to Eastern Standard Time." -f $TimeZoneId)
    $displayZone = [TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time')
    $TimeZoneId  = 'Eastern Standard Time'
}
$zoneLabel = ($displayZone.StandardName -replace '\s*Standard Time$', ' Time')

function ConvertTo-SafeHtml {
    param([Parameter(Mandatory = $false)][string] $Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function Get-LocalTimeString {
    param([Parameter(Mandatory = $false)] $Utc, [Parameter(Mandatory = $true)] $Zone)
    if ($null -eq $Utc) { return '' }
    try { return [TimeZoneInfo]::ConvertTimeFromUtc(([datetime]$Utc).ToUniversalTime(), $Zone).ToString('yyyy-MM-dd HH:mm:ss') }
    catch { return [string] $Utc }
}

function Get-Excerpt {
    param([string] $Text, [int] $Max = 700)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    if ($Text.Length -le $Max) { return $Text }
    $cut = $Text.Substring(0, $Max)
    $sp  = $cut.LastIndexOf(' ')
    if ($sp -gt ($Max * 0.6)) { $cut = $cut.Substring(0, $sp) }
    return ($cut.TrimEnd() + ' ...')
}

function Get-CleanBody {
    <#
        Copilot answers can ride in a base64 adaptive card inside the HTML body, so inspect both
        bodies and prefer whichever yields real prose. Markup is stripped for display; the untouched
        original is preserved in the JSON export.
    #>
    param([Parameter(Mandatory = $true)] $Item)

    $plain = ''
    $html  = ''
    try { if ($null -ne $Item.Body)     { $plain = [string] $Item.Body } }     catch { }
    try { if ($null -ne $Item.HTMLBody) { $html  = [string] $Item.HTMLBody } } catch { }

    foreach ($candidate in @($html, $plain)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if ($candidate -match '(?is)<Swift\s+b64="([^"]+)"') {
            try {
                $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Matches[1]))
                $payload = $decoded | ConvertFrom-Json
                $parts   = New-Object System.Collections.Generic.List[string]
                $walk = {
                    param($node)
                    if ($null -eq $node -or $node -is [string]) { return }
                    if ($node -is [System.Collections.IEnumerable]) { foreach ($c in $node) { & $walk $c }; return }
                    foreach ($p in $node.PSObject.Properties) {
                        if ($p.Name -eq 'text' -and $p.Value -is [string]) { $parts.Add($p.Value) | Out-Null }
                        else { & $walk $p.Value }
                    }
                }
                & $walk $payload
                if ($parts.Count -gt 0) { return (($parts -join "`n`n").Trim()) }
            }
            catch { }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($plain)) { return $plain.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($html)) {
        $t = $html -replace '(?is)<script.*?</script>', '' -replace '(?is)<style.*?</style>', ''
        $t = $t -replace '(?i)<br\s*/?>', "`n" -replace '(?i)</p>', "`n`n" -replace '<[^>]+>', ''
        return ([System.Net.WebUtility]::HtmlDecode($t) -replace '[ \t]+', ' ').Trim()
    }
    return ''
}

# -------------------------------------------------------------------------------------------
# Read the export. Two input shapes are supported, because the Purview export page forces a
# choice between them and Outlook COM is not always usable on an admin workstation:
#
#   A. PST  - produced when "Organize conversations into HTML transcripts" is UNCHECKED.
#             Read through Outlook COM. Richest fidelity.
#   B. HTML - produced when that box is CHECKED. No Outlook needed at all.
#
# The script picks whichever is present, preferring PST unless -PreferHtml is passed.
# -------------------------------------------------------------------------------------------
$turns     = New-Object System.Collections.Generic.List[object]
$startUtcO = $StartUtc.ToUniversalTime()
$endUtcO   = $EndUtc.ToUniversalTime()
$scanned   = 0

$psts = @(Get-ChildItem -LiteralPath $ExportPath -Recurse -Filter '*.pst' -ErrorAction SilentlyContinue)
$htmls = @(Get-ChildItem -LiteralPath $ExportPath -Recurse -Include '*.html','*.htm' -ErrorAction SilentlyContinue)

Write-Log -Message ("Export contains {0} PST file(s) and {1} HTML file(s)." -f $psts.Count, $htmls.Count)

if ($psts.Count -eq 0 -and $htmls.Count -eq 0) {
    Write-Log -Level 'ERROR' -Message "No .pst and no .html files found under $ExportPath."
    Write-Log -Message '  Export the content search from Purview > eDiscovery > Content Search > Export, download it'
    Write-Log -Message '  with the eDiscovery Export Tool, and extract the ZIP before pointing this script at it.'
    return
}

$useHtml = $PreferHtml -or ($psts.Count -eq 0)

# --- Path A: PST via Outlook COM -----------------------------------------------------------
if (-not $useHtml) {
    $outlook = $null
    try {
        Write-Log -Level 'STEP' -Message 'Starting Outlook COM to read the PST ...'
        $outlook = New-Object -ComObject Outlook.Application
        $ns = $outlook.GetNamespace('MAPI')
        Write-Log -Level 'OK' -Message ("Outlook COM ready (version {0})." -f $outlook.Version)
    }
    catch {
        $outlook = $null
        Write-Log -Level 'WARN' -Message ("Outlook COM unavailable: {0}" -f $_.Exception.Message)
        Write-Host ''
        Write-Host '  -------------------------------------------------------------------' -ForegroundColor Yellow
        Write-Host '   OUTLOOK COM COULD NOT START' -ForegroundColor Yellow
        Write-Host '  -------------------------------------------------------------------' -ForegroundColor Yellow
        Write-Host '   Common causes, in order:' -ForegroundColor White
        Write-Host '     1. Outlook has no mail profile yet. Launch Outlook once, let it' -ForegroundColor Gray
        Write-Host '        finish first-run setup, close it, then re-run this script.' -ForegroundColor Gray
        Write-Host '     2. Outlook is already running elevated (or this shell is) - COM' -ForegroundColor Gray
        Write-Host '        cannot cross elevation levels. Match them, or close Outlook.' -ForegroundColor Gray
        Write-Host '     3. A modal Outlook dialog is waiting for input off-screen.' -ForegroundColor Gray
        Write-Host '     4. New Outlook (the store app) is installed instead of classic' -ForegroundColor Gray
        Write-Host '        Outlook - the store app does not expose the COM object.' -ForegroundColor Gray
        Write-Host ''
        Write-Host '   NO OUTLOOK? Re-export with HTML transcripts instead - no COM needed:' -ForegroundColor White
        Write-Host '     Purview > eDiscovery > Content Search > <search> > Export' -ForegroundColor Green
        Write-Host '     CHECK "Organize conversations into HTML transcripts"' -ForegroundColor Green
        Write-Host '     then run this script against the extracted folder as usual.' -ForegroundColor Green
        Write-Host '  -------------------------------------------------------------------' -ForegroundColor Yellow
        Write-Host ''

        if ($htmls.Count -gt 0) {
            Write-Log -Level 'OK' -Message ("Falling back to the {0} HTML transcript file(s) already present in this export." -f $htmls.Count)
            $useHtml = $true
        }
        else {
            Write-Log -Level 'ERROR' -Message 'No HTML transcripts in this export to fall back to. Fix Outlook, or re-export with HTML transcripts checked.'
            return
        }
    }

    if ($null -ne $outlook) {
        foreach ($pst in $psts) {
            Write-Log -Level 'STEP' -Message ("Reading {0} ..." -f $pst.Name)
            $store = $null
            try {
                $ns.AddStore($pst.FullName)
                $store = $ns.Stores | Where-Object { $_.FilePath -eq $pst.FullName } | Select-Object -First 1
                if ($null -eq $store) { Write-Log -Level 'WARN' -Message 'Store did not mount; skipping.'; continue }

                $stack = New-Object System.Collections.Stack
                $stack.Push($store.GetRootFolder())

                while ($stack.Count -gt 0) {
                    $folder = $stack.Pop()
                    foreach ($sub in $folder.Folders) { $stack.Push($sub) }

                    foreach ($item in $folder.Items) {
                        $scanned++
                        $class = ''
                        try { $class = [string] $item.MessageClass } catch { continue }
                        if ($class -notlike 'IPM.SkypeTeams.Message.Copilot*') { continue }

                        $sentUtc = $null
                        foreach ($prop in @('ReceivedTime','SentOn','CreationTime')) {
                            try {
                                $v = $item.$prop
                                if ($null -ne $v -and $v -is [datetime] -and $v.Year -gt 1601) { $sentUtc = ([datetime]$v).ToUniversalTime(); break }
                            } catch { }
                        }
                        if ($null -eq $sentUtc) { continue }
                        if ($sentUtc -lt $startUtcO -or $sentUtc -ge $endUtcO) { continue }

                        $sender = ''
                        foreach ($prop in @('SenderEmailAddress','SenderName')) {
                            try { $v = [string] $item.$prop; if (-not [string]::IsNullOrWhiteSpace($v)) { $sender = $v; break } } catch { }
                        }
                        $senderName = ''
                        try { $senderName = [string] $item.SenderName } catch { }

                        $convId = ''
                        try { $convId = [string] $item.ConversationID } catch { }

                        $body = Get-CleanBody -Item $item
                        if ([string]::IsNullOrWhiteSpace($body)) { continue }

                        $rawBody = ''
                        try { $rawBody = [string] $item.Body } catch { }

                        $turns.Add([pscustomobject]@{
                            TimestampUtc   = $sentUtc
                            Sender         = $sender
                            SenderName     = $(if ([string]::IsNullOrWhiteSpace($senderName)) { $sender } else { $senderName })
                            ConversationId = $convId
                            MessageClass   = $class
                            Text           = $body
                            RawText        = $rawBody
                            SourcePst      = $pst.Name
                        }) | Out-Null
                    }
                }
            }
            catch {
                Write-Log -Level 'WARN' -Message ("Problem reading {0}: {1}" -f $pst.Name, $_.Exception.Message)
            }
            finally {
                if ($null -ne $store) {
                    try { $ns.GetType().InvokeMember('RemoveStore','InvokeMethod',$null,$ns,@($store.GetRootFolder())) | Out-Null } catch { }
                }
            }
        }
    }
}

# --- Path B: exported HTML transcripts -----------------------------------------------------
if ($useHtml) {
    Write-Log -Level 'STEP' -Message ("Parsing {0} exported HTML transcript file(s) ..." -f $htmls.Count)

    foreach ($f in $htmls) {
        $scanned++
        $raw = ''
        try { $raw = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 } catch { continue }
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }

        # eDiscovery HTML transcripts carry a header block per message. Both the classic
        # "From:/Sent on:/To:" shape and the div-per-message shape are handled by splitting on the
        # From: marker and reading the fields that follow it.
        $plain = $raw -replace '(?is)<script.*?</script>', '' -replace '(?is)<style.*?</style>', ''
        $plain = $plain -replace '(?i)<br\s*/?>', "`n" -replace '(?i)</(p|div|tr|li|h\d)>', "`n" -replace '<[^>]+>', ''
        $plain = [System.Net.WebUtility]::HtmlDecode($plain)

        foreach ($block in ($plain -split '(?im)(?=^\s*From:\s)')) {
            if ([string]::IsNullOrWhiteSpace($block)) { continue }
            if ($block -notmatch '(?im)^\s*From:\s*(.+)$') { continue }
            $fromLine = $Matches[1].Trim()

            $sentLine = ''
            if ($block -match '(?im)^\s*(?:Sent on|Sent|Date):\s*(.+)$') { $sentLine = $Matches[1].Trim() }

            $sentUtc = $null
            if (-not [string]::IsNullOrWhiteSpace($sentLine)) {
                $dt = [datetime]::MinValue
                if ([datetime]::TryParse($sentLine, [ref] $dt)) { $sentUtc = $dt.ToUniversalTime() }
            }
            if ($null -eq $sentUtc) { continue }
            if ($sentUtc -lt $startUtcO -or $sentUtc -ge $endUtcO) { continue }

            # Sender: "Display Name <address>" or a bare address.
            $sender = $fromLine; $senderName = $fromLine
            if ($fromLine -match '^(.*?)\s*<([^>]+)>\s*$') {
                $senderName = $Matches[1].Trim()
                $sender     = $Matches[2].Trim()
            }

            # Body is everything after the last header line.
            $body = $block
            foreach ($hdr in @('From','Sent on','Sent','Date','To','Cc','Subject')) {
                $body = $body -replace ("(?im)^\s*{0}:\s*.*$" -f [regex]::Escape($hdr)), ''
            }
            $body = ($body -replace '[ \t]+', ' ').Trim()
            if ([string]::IsNullOrWhiteSpace($body)) { continue }

            $turns.Add([pscustomobject]@{
                TimestampUtc   = $sentUtc
                Sender         = $sender
                SenderName     = $(if ([string]::IsNullOrWhiteSpace($senderName)) { $sender } else { $senderName })
                ConversationId = $f.BaseName
                MessageClass   = 'IPM.SkypeTeams.Message.Copilot (html transcript)'
                Text           = $body
                RawText        = $body
                SourcePst      = $f.Name
            }) | Out-Null
        }
    }
}

Write-Log -Message ("Scanned {0} source object(s); {1} Copilot message(s) with readable text in the window." -f $scanned, $turns.Count)

if ($turns.Count -eq 0) {
    Write-Log -Level 'ERROR' -Message 'No readable Copilot message bodies were found in the requested UTC window. Refusing to write a metadata-only report - a report with timestamps but no prompt or answer text looks like evidence and is not. Widen -StartUtc / -EndUtc, or confirm the export actually contains PST content rather than only Items_*.csv.'
    return
}

# -------------------------------------------------------------------------------------------
# Classify each turn: the interacting user is the prompt, anything else is the agent.
# -------------------------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($UserUpn)) {
    # Infer: the address that looks like a real mailbox and appears most often.
    $guess = $turns | Where-Object { $_.Sender -like '*@*' -and $_.Sender -notlike '*@teams.microsoft.com' } |
             Group-Object -Property Sender | Sort-Object -Property Count -Descending | Select-Object -First 1
    if ($guess) {
        $UserUpn = $guess.Name
        Write-Log -Level 'WARN' -Message ("-UserUpn was not supplied. Inferred the interacting user as '{0}' ({1} message(s)). Pass -UserUpn explicitly if that is wrong." -f $UserUpn, $guess.Count)
    }
    else {
        Write-Log -Level 'ERROR' -Message 'Could not infer the interacting user. Re-run with -UserUpn.'
        return
    }
}

foreach ($t in $turns) {
    $isUser = ($t.Sender -ieq $UserUpn) -or ($t.SenderName -ieq $UserUpn)
    Add-Member -InputObject $t -NotePropertyName 'Role' -NotePropertyValue $(if ($isUser) { 'USER' } else { 'AGENT' }) -Force
}

$agentTurns = @($turns | Where-Object { $_.Role -eq 'AGENT' })
$userTurns  = @($turns | Where-Object { $_.Role -eq 'USER' })
Write-Log -Level 'OK' -Message ("{0} prompt(s) from the user, {1} response(s) from agents." -f $userTurns.Count, $agentTurns.Count)

if ($agentTurns.Count -eq 0) {
    Write-Log -Level 'WARN' -Message 'No agent responses were classified. Check that -UserUpn matches the sender address in the export exactly.'
}

# Agent friendly name from the sending identity, for example M365AdminAgent@teams.microsoft.com.
foreach ($t in $turns) {
    $an = ''
    if ($t.Role -eq 'AGENT') {
        $an = $t.SenderName
        if ([string]::IsNullOrWhiteSpace($an) -or $an -eq $t.Sender) { $an = ($t.Sender -split '@')[0] }
    }
    Add-Member -InputObject $t -NotePropertyName 'AgentName' -NotePropertyValue $an -Force
}

# -------------------------------------------------------------------------------------------
# Group into conversations. Prefer ConversationID; fall back to a time-gap heuristic.
# -------------------------------------------------------------------------------------------
$ordered = @($turns | Sort-Object -Property TimestampUtc)
$haveConvIds = @($ordered | Where-Object { -not [string]::IsNullOrWhiteSpace($_.ConversationId) }).Count

# A ConversationID is only useful if it actually GROUPS messages. In some exports every message
# carries a distinct ID, so grouping on it yields one conversation per turn - which is no grouping
# at all and makes the report unreadable. Measure the ratio and reject the field when it is not
# doing any work.
$distinctIds = @($ordered | Where-Object { -not [string]::IsNullOrWhiteSpace($_.ConversationId) } |
                 Select-Object -ExpandProperty ConversationId -Unique).Count
$idsUseful = ($haveConvIds -ge ($ordered.Count / 2)) -and
             ($ordered.Count -gt 0) -and
             ($distinctIds -lt ($ordered.Count * 0.75))

$groups = @{}
if ($idsUseful) {
    Write-Log -Message ("Grouping by ConversationID ({0} distinct ID(s) across {1} turn(s))." -f $distinctIds, $ordered.Count)
    $n = 0
    foreach ($t in $ordered) {
        $k = $t.ConversationId
        if ([string]::IsNullOrWhiteSpace($k)) { $n++; $k = "ungrouped-$n" }
        if (-not $groups.ContainsKey($k)) { $groups[$k] = New-Object System.Collections.Generic.List[object] }
        $groups[$k].Add($t) | Out-Null
    }
}
else {
    if ($haveConvIds -gt 0) {
        Write-Log -Level 'WARN' -Message ("ConversationID does not group anything useful ({0} distinct ID(s) for {1} turn(s)), so it is being ignored." -f $distinctIds, $ordered.Count)
    }
    else {
        Write-Log -Level 'WARN' -Message 'The export carries no ConversationID.'
    }
    Write-Log -Message ("Falling back to a {0}-minute gap heuristic; conversation boundaries are approximate." -f $ConversationGapMinutes)
    $idx = 0; $prev = $null
    foreach ($t in $ordered) {
        if ($null -ne $prev -and (($t.TimestampUtc - $prev).TotalMinutes -gt $ConversationGapMinutes)) { $idx++ }
        $k = "session-{0:D3}" -f $idx
        if (-not $groups.ContainsKey($k)) { $groups[$k] = New-Object System.Collections.Generic.List[object] }
        $groups[$k].Add($t) | Out-Null
        $prev = $t.TimestampUtc
    }
}

$conversations = New-Object System.Collections.Generic.List[object]
foreach ($k in $groups.Keys) {
    $ts = @($groups[$k] | Sort-Object -Property TimestampUtc)
    $agents = @($ts | Where-Object { $_.Role -eq 'AGENT' -and -not [string]::IsNullOrWhiteSpace($_.AgentName) } |
                Select-Object -ExpandProperty AgentName -Unique)
    $conversations.Add([pscustomobject]@{
        ConversationId = $k
        StartUtc       = $ts[0].TimestampUtc
        StartLocal     = (Get-LocalTimeString -Utc $ts[0].TimestampUtc -Zone $displayZone)
        AgentName      = $(if ($agents.Count -gt 0) { ($agents -join ', ') } else { '(no agent turn)' })
        UserUpn        = $UserUpn
        TurnCount      = $ts.Count
        UserTurnCount  = @($ts | Where-Object { $_.Role -eq 'USER' }).Count
        AgentTurnCount = @($ts | Where-Object { $_.Role -eq 'AGENT' }).Count
        Turns          = $ts
    }) | Out-Null
}

if ($SortOrder -eq 'Oldest') {
    $conversations = [System.Collections.Generic.List[object]] @($conversations | Sort-Object -Property StartUtc, ConversationId)
}
else {
    $conversations = [System.Collections.Generic.List[object]] @($conversations | Sort-Object -Property @{ Expression = 'StartUtc'; Descending = $true }, ConversationId)
}

Write-Log -Level 'OK' -Message ("{0} conversation(s), {1} total turn(s)." -f $conversations.Count, $turns.Count)
Write-Log -Message ("Sort order      : conversations {0} first; turns always oldest -> newest." -f $SortOrder.ToLowerInvariant())

# -------------------------------------------------------------------------------------------
# Output
# -------------------------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null }
$stamp   = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$written = New-Object System.Collections.Generic.List[string]

# CSV - one row per turn
$csvPath = Join-Path $OutputFolder "FirstPartyAgent-Turns-$stamp.csv"
if ($PSCmdlet.ShouldProcess($csvPath, 'Write CSV')) {
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($c in $conversations) {
        $i = 0
        foreach ($t in $c.Turns) {
            $i++
            $rows.Add([pscustomobject]@{
                ConversationId = $c.ConversationId
                AgentName      = $c.AgentName
                TurnNumber     = $i
                Role           = $t.Role
                Sender         = $t.Sender
                SenderName     = $t.SenderName
                TimestampLocal = (Get-LocalTimeString -Utc $t.TimestampUtc -Zone $displayZone)
                TimestampUtc   = $t.TimestampUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
                CharCount      = $t.Text.Length
                Excerpt        = (Get-Excerpt $t.Text 300)
                Text           = ($t.Text -replace "`r`n", ' ' -replace "`n", ' ')
                SourcePst      = $t.SourcePst
            }) | Out-Null
        }
    }
    [System.IO.File]::WriteAllText($csvPath, (($rows | ConvertTo-Csv -NoTypeInformation) -join "`r`n"), $utf8Bom)
    $written.Add($csvPath) | Out-Null
    Write-Log -Level 'OK' -Message ("CSV written: {0} ({1} turn row(s))" -f $csvPath, $rows.Count)
}

# JSON - verbatim originals for chain of custody
$jsonPath = Join-Path $OutputFolder "FirstPartyAgent-Transcripts-$stamp.json"
if ($PSCmdlet.ShouldProcess($jsonPath, 'Write JSON')) {
    $payload = [pscustomobject]@{
        GeneratedUtc      = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        ExportPath        = $ExportPath
        InteractingUser   = $UserUpn
        WindowStartUtc    = $startUtcO.ToString('yyyy-MM-ddTHH:mm:ssZ')
        WindowEndUtc      = $endUtcO.ToString('yyyy-MM-ddTHH:mm:ssZ')
        DisplayTimeZone   = $TimeZoneId
        SortOrder         = ("Conversations {0} first; turns oldest to newest." -f $SortOrder.ToLowerInvariant())
        ConversationCount = $conversations.Count
        TurnCount         = $turns.Count
        SourceOfTruth     = 'Exchange Online mailbox items (ItemClass IPM.SkypeTeams.Message.Copilot*) exported via Microsoft Purview eDiscovery.'
        Note              = 'First-party Microsoft 365 Copilot agents do not write to the Dataverse conversationtranscript table. Purview DSPM Activity explorer renders the prompt but has no Response field for these agents, so the mailbox export is the authoritative source for the agent response text.'
        Conversations     = $conversations
    }
    [System.IO.File]::WriteAllText($jsonPath, ($payload | ConvertTo-Json -Depth 10), $utf8Bom)
    $written.Add($jsonPath) | Out-Null
    Write-Log -Level 'OK' -Message "JSON written: $jsonPath"
}

# HTML - the review deliverable
$htmlPath = Join-Path $OutputFolder "FirstPartyAgent-Transcripts-$stamp.html"
if ($PSCmdlet.ShouldProcess($htmlPath, 'Write HTML')) {

    $agentNames   = @($conversations | Select-Object -ExpandProperty AgentName -Unique | Sort-Object)
    $agentOptions = ($agentNames | ForEach-Object { "<option value=""$(ConvertTo-SafeHtml $_)"">$(ConvertTo-SafeHtml $_)</option>" }) -join ''
    $oldest = ($turns | Measure-Object -Property TimestampUtc -Minimum).Minimum
    $newest = ($turns | Measure-Object -Property TimestampUtc -Maximum).Maximum
    $generatedLcl = Get-LocalTimeString -Utc ([datetime]::UtcNow) -Zone $displayZone

    $cards = foreach ($c in $conversations) {
        $flags = New-Object System.Collections.Generic.List[string]
        if ($c.AgentTurnCount -eq 0) { $flags.Add('<span class="pill idle">No agent response</span>') | Out-Null }
        if ($c.UserTurnCount -eq 0)  { $flags.Add('<span class="pill idle">No user turns</span>') | Out-Null }

        $turnHtml = foreach ($t in $c.Turns) {
            $clean   = $t.Text
            $isLong  = $clean.Length -gt 700
            $cls     = if ($t.Role -eq 'USER') { 'turn user' } else { 'turn agent' }
            $who     = if ($t.Role -eq 'USER') { $t.SenderName } else { $t.AgentName }
            $tsLocal = Get-LocalTimeString -Utc $t.TimestampUtc -Zone $displayZone

            $bodyHtml = if ($isLong) {
                "<div class=""short"">$(ConvertTo-SafeHtml (Get-Excerpt $clean 700))</div>" +
                "<div class=""full"">$(ConvertTo-SafeHtml $clean)</div>" +
                "<button class=""more"" onclick=""tog(this)"">Show full text ($($clean.Length) chars)</button>"
            } else {
                "<div class=""short only"">$(ConvertTo-SafeHtml $clean)</div>"
            }

            "<div class=""$cls""><div class=""hd""><span class=""who"">$(ConvertTo-SafeHtml $who)</span><span class=""role"">$($t.Role)</span><span class=""ts"" title=""$($t.TimestampUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')) UTC"">$(ConvertTo-SafeHtml $tsLocal)</span></div>$bodyHtml</div>"
        }

        $blob   = ConvertTo-SafeHtml ((($c.Turns | ForEach-Object { Get-Excerpt $_.Text 400 }) -join ' ') + ' ' + $c.AgentName + ' ' + $c.ConversationId)
        $dayKey = ($c.StartLocal -split ' ')[0]
        $epoch  = [int64] ([datetimeoffset]::new($c.StartUtc, [timespan]::Zero)).ToUnixTimeSeconds()

        @"
<section class="conv" data-agent="$(ConvertTo-SafeHtml $c.AgentName)" data-day="$dayKey" data-epoch="$epoch" data-blob="$blob">
  <div class="chd">
    <div>
      <h2>$(ConvertTo-SafeHtml $c.AgentName)</h2>
      <div class="meta">$(ConvertTo-SafeHtml $c.StartLocal) $(ConvertTo-SafeHtml $zoneLabel) &middot; $($c.TurnCount) turn(s): $($c.UserTurnCount) prompt(s), $($c.AgentTurnCount) response(s) &middot; $(ConvertTo-SafeHtml $c.UserUpn)</div>
    </div>
    <div class="flags">$([string]::Join(' ', $flags))</div>
  </div>
  <div class="ids"><span><b>Conversation:</b> $(ConvertTo-SafeHtml $c.ConversationId)</span><span><b>Start (UTC):</b> $($c.StartUtc.ToString('yyyy-MM-ddTHH:mm:ssZ'))</span></div>
  <div class="thread">$([string]::Join('', $turnHtml))</div>
</section>
"@
    }

    $html = @"
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>First-Party Copilot Agent Conversation Report</title>
<style>
:root{--bd:#d8dee4;--mut:#66717b;--acc:#0f6cbd;--bg:#f7f9fb;--ink:#1f2933}
*{box-sizing:border-box}
body{font-family:"Segoe UI",Arial,sans-serif;margin:0;background:var(--bg);color:var(--ink)}
header{background:#fff;border-bottom:1px solid var(--bd);padding:22px 28px}
h1{margin:0 0 6px;font-size:22px;font-weight:600}
.sub{color:var(--mut);font-size:13px;line-height:1.55}
.cards{display:flex;gap:12px;flex-wrap:wrap;padding:18px 28px 0}
.card{background:#fff;border:1px solid var(--bd);border-radius:6px;padding:12px 16px;min-width:140px}
.card .v{font-size:23px;font-weight:600;color:var(--acc)}
.card .k{font-size:11px;color:var(--mut);text-transform:uppercase;letter-spacing:.35px;margin-top:3px}
.note{margin:16px 28px 0;padding:12px 16px;border-radius:6px;font-size:13px;line-height:1.55;background:#f0f9f0;border:1px solid #b7e0b7}
.note.horizon{background:#eaf3fb;border-color:#a9cded}
.note code{background:#e3f0e3;padding:1px 5px;border-radius:3px}
.note.horizon code{background:#d7e8f7}
.controls{padding:17px 28px 9px;display:flex;gap:10px;flex-wrap:wrap;align-items:center}
input,select,button{padding:8px 10px;border:1px solid var(--bd);border-radius:4px;font-size:13px;font-family:inherit;background:#fff}
input#q{min-width:320px}
button{cursor:pointer}
#count{color:var(--mut);font-size:12px}
.wrap{padding:10px 28px 30px}
.conv{background:#fff;border:1px solid var(--bd);border-radius:7px;margin-bottom:16px;overflow:hidden}
.conv.hide{display:none}
.chd{display:flex;justify-content:space-between;align-items:flex-start;gap:14px;padding:13px 17px;background:#f2f5f8;border-bottom:1px solid var(--bd)}
.chd h2{margin:0;font-size:15px;font-weight:600}
.meta{color:var(--mut);font-size:12px;margin-top:3px}
.pill{display:inline-block;font-size:11px;padding:2px 8px;border-radius:10px;margin-left:5px}
.pill.idle{background:#eceff2;color:#5a646e}
.ids{display:flex;flex-wrap:wrap;gap:16px;padding:8px 17px;background:#fafbfc;border-bottom:1px solid #eef1f4;font-size:11px;color:var(--mut);font-family:Consolas,monospace}
.thread{padding:14px 17px}
.turn{border-left:3px solid var(--bd);padding:9px 13px;margin-bottom:10px;border-radius:0 5px 5px 0;background:#fbfcfd}
.turn.user{border-left-color:var(--acc);background:#eef5fc}
.turn.agent{border-left-color:#8a9099}
.turn .hd{display:flex;gap:10px;align-items:baseline;margin-bottom:5px}
.turn .who{font-weight:600;font-size:12px}
.turn .role{font-size:10px;letter-spacing:.4px;color:var(--mut);text-transform:uppercase}
.turn .ts{margin-left:auto;font-size:11px;color:var(--mut);font-variant-numeric:tabular-nums}
.turn .short,.turn .full{white-space:pre-wrap;font-size:13.5px;line-height:1.55}
.turn .full{display:none}
.turn.open .short{display:none}
.turn.open .full{display:block}
.turn .more{margin-top:6px;font-size:11.5px;padding:3px 9px;background:#eef1f4;border:1px solid var(--bd)}
footer{padding:0 28px 40px;color:var(--mut);font-size:12px;line-height:1.6}
</style></head><body>
<header>
  <h1>First-Party Copilot Agent Conversation Report</h1>
  <div class="sub">
    <div>Interacting user: $(ConvertTo-SafeHtml $UserUpn)</div>
    <div>Export source: $(ConvertTo-SafeHtml $ExportPath)</div>
    <div>Sort: conversations $(if ($SortOrder -eq 'Oldest') { 'oldest first' } else { 'newest first' }) by start time; turns within a conversation always oldest to newest.</div>
    <div>Generated: $(ConvertTo-SafeHtml $generatedLcl) $(ConvertTo-SafeHtml $zoneLabel) &middot; all times shown in $(ConvertTo-SafeHtml $zoneLabel); UTC retained in the exports</div>
  </div>
</header>
<div class="cards">
  <div class="card"><div class="v">$($conversations.Count)</div><div class="k">Conversations</div></div>
  <div class="card"><div class="v">$($turns.Count)</div><div class="k">Total turns</div></div>
  <div class="card"><div class="v">$($userTurns.Count)</div><div class="k">Prompts</div></div>
  <div class="card"><div class="v">$($agentTurns.Count)</div><div class="k">Agent responses</div></div>
  <div class="card"><div class="v">$($agentNames.Count)</div><div class="k">Agents</div></div>
</div>
<div class="note horizon">
  <strong>Coverage for this export:</strong> the oldest recovered message is
  <code>$(ConvertTo-SafeHtml (Get-LocalTimeString -Utc $oldest -Zone $displayZone))</code> and the newest is
  <code>$(ConvertTo-SafeHtml (Get-LocalTimeString -Utc $newest -Zone $displayZone))</code>.
  This report is complete only for the window that the underlying Content Search covered and that
  mailbox retention still holds. Widen the search, not this script, to see more.
</div>
<div class="note">
  <strong>Evidence source:</strong> Exchange Online mailbox items with item class
  <code>IPM.SkypeTeams.Message.Copilot*</code>, exported through Microsoft Purview eDiscovery.
  First-party Microsoft 365 Copilot agents do <em>not</em> write to the Dataverse
  <code>conversationtranscript</code> table, so the Copilot Studio exporter cannot see them, and Purview
  DSPM Activity explorer renders the prompt but has <strong>no Response field at all</strong> for these
  agents. Prompts and responses are stored as separate mailbox items and are paired here by
  <strong>sender identity</strong>: messages from <code>$(ConvertTo-SafeHtml $UserUpn)</code> are prompts,
  everything else is the agent. Long turns are shown as excerpts with a <em>Show full text</em> control;
  the untouched original is preserved in the JSON export.
</div>
<div class="controls">
  <input id="q" type="search" placeholder="Filter by prompt text, answer text, agent, conversation ID...">
  <select id="fAgent"><option value="">All agents</option>$agentOptions</select>
  <input id="dFrom" type="date" title="Conversations starting on or after this date ($zoneLabel)">
  <input id="dTo" type="date" title="Conversations starting on or before this date ($zoneLabel)">
  <select id="fSort" title="Chronological order">
    <option value="desc"$(if ($SortOrder -ne 'Oldest') { ' selected' })>Newest first</option>
    <option value="asc"$(if ($SortOrder -eq 'Oldest') { ' selected' })>Oldest first</option>
  </select>
  <button onclick="expandAll()">Expand all text</button>
  <button onclick="resetAll()">Reset filters</button>
  <span id="count"></span>
</div>
<div class="wrap" id="wrap">$([string]::Join('', $cards))</div>
<footer>Use the HTML for review, the CSV for filtering and pivoting, and the JSON for structured evidence and chain of custody. Content is sensitive - handle per your organization's retention and privacy requirements.</footer>
<script>
var q=document.getElementById('q'),ag=document.getElementById('fAgent'),
    df=document.getElementById('dFrom'),dt=document.getElementById('dTo'),
    so=document.getElementById('fSort'),wrap=document.getElementById('wrap'),ct=document.getElementById('count');
var defaultSort='$(if ($SortOrder -eq 'Oldest') { 'asc' } else { 'desc' })';
function reorder(){
  var dir=so.value==='asc'?1:-1;
  var rows=Array.prototype.slice.call(wrap.querySelectorAll('.conv'));
  rows.sort(function(a,b){
    var ea=parseInt(a.dataset.epoch||'0',10),eb=parseInt(b.dataset.epoch||'0',10);
    if(!ea&&!eb)return 0; if(!ea)return 1; if(!eb)return -1;
    if(ea===eb)return 0; return ea<eb?dir:-dir;
  });
  var frag=document.createDocumentFragment();
  rows.forEach(function(r){frag.appendChild(r)});
  wrap.appendChild(frag);
}
function apply(){
  var query=q.value.toLowerCase(),a=ag.value,from=df.value,to=dt.value,shown=0,all=document.querySelectorAll('.conv');
  all.forEach(function(r){
    var okText=!query||(r.dataset.blob||'').toLowerCase().indexOf(query)>-1;
    var okAgent=!a||r.dataset.agent===a;
    var d=r.dataset.day||'';
    var show=okText&&okAgent&&(!from||(d&&d>=from))&&(!to||(d&&d<=to));
    r.classList.toggle('hide',!show);
    if(show)shown++;
  });
  ct.textContent=shown+' of '+all.length+' conversations shown';
}
function tog(b){b.parentNode.classList.toggle('open');b.textContent=b.parentNode.classList.contains('open')?'Collapse':'Show full text';}
function expandAll(){document.querySelectorAll('.turn').forEach(function(t){if(t.querySelector('.more'))t.classList.add('open')});}
function resetAll(){q.value='';ag.value='';df.value='';dt.value='';so.value=defaultSort;document.querySelectorAll('.turn').forEach(function(t){t.classList.remove('open')});reorder();apply();}
[q,ag,df,dt].forEach(function(x){x.addEventListener('input',apply)});
so.addEventListener('change',reorder);
reorder(); apply();
</script></body></html>
"@
    [System.IO.File]::WriteAllText($htmlPath, $html, $utf8Bom)
    $written.Add($htmlPath) | Out-Null
    Write-Log -Level 'OK' -Message "HTML written: $htmlPath"
}

Write-Host ''
Write-Host '  Open the HTML report to review conversations:' -ForegroundColor White
Write-Host ("    {0}" -f $htmlPath) -ForegroundColor Cyan
Write-Host ''
