<#
.SYNOPSIS
    Generates a Copilot Chat compliance report from an extracted Microsoft Purview
    eDiscovery export. Runs entirely offline - no tenant connection required.

.DESCRIPTION
    Parses Copilot Chat / BizChat activity from a Purview eDiscovery export and emits:

      * CopilotChat-ComplianceReport.csv   - flat, reviewer-friendly, one row per interaction
      * CopilotChat-ComplianceReport.json  - full fidelity, every extracted field
      * CopilotChat-ComplianceReport.html  - interactive dashboard

    Supports both native message format exports (with TeamsMessagesData folders) and 
    CSV-only exports (metadata only). When only CSV is available, extracts Copilot item 
    class, actor, timestamps, and entrypoint from Items CSV metadata.

.PARAMETER ExportPath
    Folder containing the extracted eDiscovery export (parent of Items/, PSTs/, or 
    Exchange\...\TeamsMessagesData).
    
    ⚠ IMPORTANT: To capture actual prompt/response text, the export MUST include the 
    native message format (TeamsMessagesData folder). In Purview, select "Export results 
    in native format" or "Exchange native format" — not just the report CSV.

.PARAMETER StartUtc / EndUtc
    Inclusive/exclusive UTC bounds on message time. Defaults to the last 7 days.

.PARAMETER OutputFolder
    Destination for the generated report files.

.PARAMETER TimeZoneId
    Windows time zone id used for the human-readable Timestamp column, e.g. 'Eastern Standard Time'.

.EXAMPLE
    .\Get-CopilotComplianceReport-ExportOnly.ps1 -ExportPath C:\Export -OutputFolder C:\Reports `
        -TimeZoneId 'Eastern Standard Time'
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string] $ExportPath,
    [datetime] $StartUtc = ((Get-Date).AddDays(-7)),
    [datetime] $EndUtc = (Get-Date),
    [string] $OutputFolder = (Join-Path (Get-Location) 'CopilotComplianceReport'),
    [string] $TimeZoneId = 'UTC',
    [string] $AuditEventsPath
)

$ErrorActionPreference = 'Stop'

# ---- Utilities ----
function ConvertTo-Array { param ($value)
    if ($value -is [array]) { return $value }
    if ($null -eq $value) { return @() }
    return @($value)
}

function ConvertTo-HtmlEncoded {
    param($Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Get-EmailFromDisplay {
    param([string]$Value)
    if (-not $Value) { return $null }
    $m = [regex]::Match($Value, '<([^>]+)>')
    if ($m.Success) { return $m.Groups[1].Value.Trim().ToLowerInvariant() }
    if ($Value -match '@') { return $Value.Trim().ToLowerInvariant() }
    return $null
}

function Parse-DateTimeOffsetSafe {
    param($Value)
    if ($null -eq $Value) { return $null }
    try {
        return [datetimeoffset]::Parse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
    } catch {
        return $null
    }
}

function Resolve-CopilotEntrypoint {
    param(
        [string]$AppIdentity,
        [string]$AppHost
    )

    if ($AppIdentity -match 'Copilot\.M365Copilot\.WebChat') {
        return 'Copilot Chat web URL (m365.cloud.microsoft/chat)'
    }
    if ($AppIdentity -match 'Copilot\.M365Copilot\.Bizchat') {
        if ($AppHost -match 'BizChat') { return 'Microsoft 365 Copilot Chat / BizChat' }
        if ($AppHost -match 'Outlook') { return 'Copilot in Outlook (Bizchat identity)' }
        if ($AppHost -match 'Teams') { return 'Copilot app in Teams (Bizchat identity)' }
        if ($AppHost -match 'Office|M365App|OfficeCopilot') { return 'Microsoft 365 Copilot Chat in Microsoft 365 app / Office host' }
        if ($AppHost -match 'Bing|Edge') { return 'Copilot Chat through Bing/Edge host' }
        if ($AppHost -match 'Word') { return 'Copilot in Word (Bizchat identity)' }
        if ($AppHost -match 'Excel') { return 'Copilot in Excel (Bizchat identity)' }
        if ($AppHost -match 'PowerPoint') { return 'Copilot in PowerPoint (Bizchat identity)' }
        return "Copilot Bizchat (host not mapped: $AppHost)"
    }
    if ($AppHost -match 'BizChat') { return 'Microsoft 365 Copilot Chat / BizChat (host-derived)' }
    if ($AppHost -match 'Office|M365App|OfficeCopilot') { return 'Microsoft 365 Copilot Chat in Microsoft 365 app / Office host (host-derived)' }
    if ($AppHost -match 'Outlook') { return 'Copilot in Outlook (host-derived)' }
    if ($AppHost -match 'Teams') { return 'Copilot in Teams (host-derived)' }
    if ($AppHost -match 'Bing|Edge') { return 'Copilot Chat through Bing/Edge host (host-derived)' }
    return 'Unknown (check AppIdentity/AppHost in audit payload)'
}

function Import-CopilotAuditEvents {
    <#
      Ingests audit records exported from Search-UnifiedAuditLog (CSV or JSON) and extracts
      the entrypoint fields needed by compliance reviewers:
        - AppIdentity
        - AppHost
        - CopilotEventData.ConversationId
        - user principal / actor
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) { throw "Audit events file not found: $Path" }

    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($ext -eq '.csv') {
        $records = @(Import-Csv -Path $Path)
    } else {
        $raw = Get-Content -Path $Path -Raw
        $parsed = $raw | ConvertFrom-Json
        if ($parsed -is [array]) { $records = @($parsed) } else { $records = @($parsed) }
    }

    $events = New-Object System.Collections.Generic.List[object]
    foreach ($r in $records) {
        $audit = $null
        if ($r.PSObject.Properties.Name -contains 'AuditData' -and $r.AuditData) {
            try { $audit = $r.AuditData | ConvertFrom-Json -ErrorAction Stop } catch { $audit = $null }
        } elseif ($r.PSObject.Properties.Name -contains 'CopilotEventData') {
            $audit = $r
        } elseif ($r.PSObject.Properties.Name -contains 'ThreadId') {
            $audit = $r
        }

        if (-not $audit) { continue }

        $ced = $null
        if ($audit.PSObject.Properties.Name -contains 'CopilotEventData' -and $audit.CopilotEventData) {
            if ($audit.CopilotEventData -is [string]) {
                try { $ced = $audit.CopilotEventData | ConvertFrom-Json -ErrorAction Stop } catch { $ced = $null }
            } else {
                $ced = $audit.CopilotEventData
            }
        } else {
            $ced = $audit
        }
        if (-not $ced) { continue }

        $conversationId = [string]$ced.ConversationId
        if (-not $conversationId) { $conversationId = [string]$ced.conversationId }

        $threadId = [string]$ced.ThreadId
        if (-not $threadId) { $threadId = [string]$ced.ThreadID }
        if (-not $threadId) { $threadId = [string]$r.ThreadId }
        if (-not $conversationId -and -not $threadId) { continue }

        $appIdentity = [string]$audit.AppIdentity
        if (-not $appIdentity) { $appIdentity = [string]$ced.AppIdentity }
        if (-not $appIdentity) { $appIdentity = [string]$ced.appIdentity }

        $appHost = [string]$audit.AppHost
        if (-not $appHost) { $appHost = [string]$ced.AppHost }
        if (-not $appHost) { $appHost = [string]$ced.appHost }
        if (-not $appHost) { $appHost = [string]$r.Surface }

        $actor = [string]$audit.UserId
        if (-not $actor) { $actor = [string]$r.UserIds }
        if (-not $actor) { $actor = [string]$r.UserId }
        if (-not $actor) { $actor = [string]$r.Actor }
        $ts = $null
        foreach ($candidate in @($r.CreationDate, $r.CreationTime, $audit.CreationTime, $audit.CreationDate, $r.TimestampUtc, $r.TimeGenerated)) {
            $ts = Parse-DateTimeOffsetSafe -Value $candidate
            if ($ts) { break }
        }

        $events.Add([pscustomobject]@{
            ConversationId = $conversationId
            ThreadId = $threadId
            ActorEmail = if ($actor) { $actor.Trim().ToLowerInvariant() } else { $null }
            TimestampUtc = $ts
            AppIdentity = $appIdentity
            AppHost = $appHost
            CopilotEntrypoint = Resolve-CopilotEntrypoint -AppIdentity $appIdentity -AppHost $appHost
        })
    }

    return $events.ToArray()
}

function Get-CopilotLinkFacts {
    <#
      Reads the LinksBlob property of a message. LinksBlob is the authoritative record of
      what Copilot actually retrieved for the answer; it is a JSON array embedded as a JSON
      *string*, so every structural quote arrives escaped. Entry shapes seen in the wild:

        {"@type":"WebSearchQuery","url":"queries=[\"term\"]","isCitedInResponse":true}
        {"@type":"CITATION","url":"https://...","linkMetadata":{...providerDisplayName,Title,snippet...}}
        {"@type":"...","linkMetadata":{...},"linkMetadataType":"SourceAttribution"}

      WebSearchQuery.url carries the literal terms sent to the search backend (Bing). This is
      the only trustworthy source of search keywords - the narrative text of the answer must
      never be regex-scraped for them, because that returns arbitrary prose.
    #>
    param ([string]$Json)

    $out = [pscustomobject]@{
        WebSearchQueries = @()
        Citations        = @()
        HasLinksBlob     = $false
    }

    $m = [regex]::Match($Json, '(?s)"LinksBlob"\s*:\s*"(.*?)"\s*,\s*"LinksBlob@is\.Queryable"')
    if (-not $m.Success) { return $out }
    $out.HasLinksBlob = $true

    $blob = $m.Groups[1].Value -replace '\\\\"', '"' -replace '\\"', '"'

    foreach ($q in [regex]::Matches($blob, '"@type"\s*:\s*"WebSearchQuery"\s*,\s*"url"\s*:\s*"queries=\[(?<terms>.*?)\]"')) {
        foreach ($term in [regex]::Matches($q.Groups['terms'].Value, '"([^"]+)"')) {
            $out.WebSearchQueries += $term.Groups[1].Value
        }
    }

    foreach ($c in [regex]::Matches($blob, '"@type"\s*:\s*"CITATION"\s*,\s*"url"\s*:\s*"(?<url>[^"]+)"')) {
        $url = $c.Groups['url'].Value
        # Pull the human-readable title that sits alongside this citation, when present.
        $title = ''
        $tM = [regex]::Match($blob.Substring($c.Index), '"providerDisplayName"\s*:\s*"([^"]{1,300})"')
        if ($tM.Success) { $title = $tM.Groups[1].Value }
        $out.Citations += [pscustomobject]@{ Url = $url; Title = $title }
    }

    $out.WebSearchQueries = @($out.WebSearchQueries | Select-Object -Unique)
    $out.Citations = @($out.Citations | Group-Object Url | ForEach-Object { $_.Group[0] })
    return $out
}

function ConvertFrom-CopilotJsonBlock {
    param ([string]$Json)
    $result = [pscustomobject]@{
        MessageFrom      = $null
        Topic            = $null
        CreatedUtc       = $null
        ItemId           = $null
        ConversationId   = $null
        ThreadId         = $null
        Content          = $null
        SenderName       = $null
        SenderEmail      = $null
        Attachments      = @()
        WebSearchQueries = @()
        Citations        = @()
        IsBot            = $false
        ParseOk          = $false
    }

    $outer = $null
    try { $outer = $Json | ConvertFrom-Json -ErrorAction Stop } catch { $outer = $null }

    # CreatedDateTime is always extracted by regex against the raw text, never via the parsed
    # object. ConvertFrom-Json's ISO-8601 "...Z" string auto-detection silently produces a
    # [DateTime] instead of leaving the value as a string, and observably does this
    # INCONSISTENTLY between sibling blocks in the very same export (some parse back out as a
    # true-UTC DateTimeOffset, others as if they were local machine time) - there is no reliable
    # way to trust its Kind. Regexing the original "CreatedDateTime":"...Z" text once, up front,
    # sidesteps that entirely and gives every block (both parse paths below) identical handling.
    $dtM = [regex]::Match($Json, '"CreatedDateTime"\s*:\s*"([^"]+)"')
    if ($dtM.Success) {
        try {
            $result.CreatedUtc = [datetimeoffset]::Parse($dtM.Groups[1].Value,
                [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        } catch { }
    }

    # Conversation and thread identity are likewise regexed from raw text so they survive the
    # malformed-block fallback path below. ConversationId is what makes two visually identical
    # threads distinguishable, so it must never be lost.
    $convM = [regex]::Match($Json, '"CopilotConversationId"\s*:\s*"([^"]+)"')
    if ($convM.Success) { $result.ConversationId = $convM.Groups[1].Value }
    $thrM = [regex]::Match($Json, '"ThreadId"\s*:\s*"([^"]+)"')
    if ($thrM.Success) { $result.ThreadId = $thrM.Groups[1].Value }

    $linkFacts = Get-CopilotLinkFacts -Json $Json
    $result.WebSearchQueries = $linkFacts.WebSearchQueries
    $result.Citations = $linkFacts.Citations

    if ($outer) {
        # ---- normal path: the whole block parsed cleanly
        $itemData = $null
        if ($outer.PSObject.Properties.Name -contains 'ItemData' -and $outer.ItemData) {
            try { $itemData = $outer.ItemData | ConvertFrom-Json -ErrorAction Stop } catch { }
        }
        $recipients = $null
        if ($outer.PSObject.Properties.Name -contains 'RecipientsPreview' -and $outer.RecipientsPreview) {
            try { $recipients = $outer.RecipientsPreview | ConvertFrom-Json -ErrorAction Stop } catch { }
        }
        if ($recipients -and $recipients.Sender) {
            $result.SenderName  = [string]$recipients.Sender.Name
            $result.SenderEmail = [string]$recipients.Sender.EmailAddress
        }
        if ($itemData) {
            $result.MessageFrom = [string]$itemData.messageFrom
            $result.Content     = [string]$itemData.content
            if ($itemData.topic) { $result.Topic = [string]$itemData.topic }
        }
        if (-not $result.Topic -and $outer.Topic) { $result.Topic = [string]$outer.Topic }
        if ($outer.SkypeItemId) { $result.ItemId = [string]$outer.SkypeItemId }

        # Attachment detection: itemData.properties (string) -> .copilotMetadata (string) ->
        # .messageAnnotations[] where messageAnnotationType = "LocalFile".
        if ($itemData -and $itemData.properties) {
            try {
                $propsOuter = $itemData.properties | ConvertFrom-Json -ErrorAction Stop
                if ($propsOuter.copilotMetadata) {
                    $copMeta = $propsOuter.copilotMetadata | ConvertFrom-Json -ErrorAction Stop
                    foreach ($ann in (ConvertTo-Array $copMeta.messageAnnotations)) {
                        if ($ann.messageAnnotationType -eq 'LocalFile' -and $ann.text) {
                            $result.Attachments += [string]$ann.text
                        }
                    }
                }
            } catch { }
        }
        $result.ParseOk = $true
    }
    else {
        # ---- fallback path: whole-block JSON is malformed (Adaptive Card content)
        $topicM = [regex]::Match($Json, '"Topic"\s*:\s*"([^"]*)"')
        if ($topicM.Success) { $result.Topic = $topicM.Groups[1].Value }
        $idM = [regex]::Match($Json, '"SkypeItemId"\s*:\s*"([^"]+)"')
        if ($idM.Success) { $result.ItemId = $idM.Groups[1].Value }
        $fromM = [regex]::Match($Json, '\\\\?"messageFrom\\\\?"\s*:\s*\\\\?"([^\\"]+)\\\\?"')
        if ($fromM.Success) { $result.MessageFrom = $fromM.Groups[1].Value }

        # Isolate the embedded "swift b64=...&quot;" adaptive-card payload and decode it.
        $swiftM = [regex]::Match($Json, '(?s)b64=.*?quot;(.*?)&quot;')
        if ($swiftM.Success) {
            $cleaned = ($swiftM.Groups[1].Value -replace '[^A-Za-z0-9+/=]', '')
            if ($cleaned.Length -gt 0) {
                try {
                    $cardJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($cleaned))
                    $texts = [regex]::Matches($cardJson, '"text"\s*:\s*"((?:[^"\\]|\\.)*)"') | ForEach-Object {
                        ($_.Groups[1].Value -replace '\\n', "`n" -replace '\\"', '"' -replace '\\/', '/')
                    }
                    if ($texts) { $result.Content = ($texts -join "`n`n") }
                } catch { }
            }
        }
        $result.ParseOk = ($null -ne $result.CreatedUtc)
    }

    # Prefer the Skype-identity prefix on messageFrom: "8:orgid:{guid}" = human, "28:{guid}" = Copilot service
    if ($result.MessageFrom -match '^28:') { $result.IsBot = $true }
    elseif ($result.MessageFrom -match '^8:orgid:') { $result.IsBot = $false }
    else {
        $result.IsBot = ($result.SenderName -imatch 'Microsoft 365 Chat|Copilot') -or
                        ($result.SenderEmail -imatch '@(teams\.microsoft\.com|copilot\.microsoft\.com)$')
    }

    return $result
}

function Import-CopilotChatHtmlExport {
    param (
        [Parameter(Mandatory)] [string] $Path,
        [datetime] $StartUtc = [datetime]::MinValue,
        [datetime] $EndUtc = [datetime]::MaxValue
    )

    $htmlFiles = @(Get-ChildItem -Path $Path -Filter '*.html' -Recurse -ErrorAction SilentlyContinue |
                   Where-Object { $_.DirectoryName -imatch 'TeamsMessagesData' })

    $turns = New-Object System.Collections.Generic.List[object]
    $rawMessages = New-Object System.Collections.Generic.List[object]
    $skippedNoJson = New-Object System.Collections.Generic.List[string]

    foreach ($file in $htmlFiles) {
        $raw = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $raw) { continue }

        $blockMatches = [regex]::Matches($raw, '<script type="application/json"><!\[CDATA\[(?<json>.*?)\]\]></script>', 'Singleline')
        if ($blockMatches.Count -eq 0) {
            # Rendered Adaptive Card fragments carry no structured data; the same answer is
            # already present, with metadata, in the correspondingly-named conversation file.
            $skippedNoJson.Add($file.Name)
            continue
        }

        $messages = @()
        foreach ($bm in $blockMatches) {
            $parsed = ConvertFrom-CopilotJsonBlock -Json $bm.Groups['json'].Value
            if ($parsed.ParseOk) {
                $messages += $parsed
                $rawMessages.Add([pscustomobject]@{
                    SourceFile       = $file.Name
                    ItemId           = $parsed.ItemId
                    ConversationId   = $parsed.ConversationId
                    ThreadId         = $parsed.ThreadId
                    CreatedUtc       = if ($parsed.CreatedUtc) { $parsed.CreatedUtc.UtcDateTime.ToString('o') } else { $null }
                    Role             = if ($parsed.IsBot) { 'copilot' } else { 'user' }
                    MessageFrom      = $parsed.MessageFrom
                    SenderName       = $parsed.SenderName
                    SenderEmail      = $parsed.SenderEmail
                    Topic            = $parsed.Topic
                    Content          = $parsed.Content
                    Attachments      = @($parsed.Attachments)
                    WebSearchQueries = @($parsed.WebSearchQueries)
                    Citations        = @($parsed.Citations)
                })
            }
        }

        # Group messages into turns (split at each user message)
        $turn = $null
        foreach ($msg in ($messages | Sort-Object CreatedUtc)) {
            if (-not $msg.IsBot) {
                if ($turn) { $turns.Add($turn) }
                $turn = [pscustomobject]@{
                    Topic            = $msg.Topic
                    ItemId           = $msg.ItemId
                    ConversationId   = $msg.ConversationId
                    ThreadId         = $msg.ThreadId
                    PromptText       = $msg.Content
                    PromptSender     = "$($msg.SenderName) <$($msg.SenderEmail)>"
                    ResponseText     = @()
                    Attachments      = @($msg.Attachments)
                    WebSearchQueries = @($msg.WebSearchQueries)
                    Citations        = @($msg.Citations)
                    PromptUtc        = $msg.CreatedUtc
                    LastUtc          = $msg.CreatedUtc
                    SourceFile       = $file.FullName
                }
            }
            elseif ($turn) {
                $turn.ResponseText     += $msg.Content
                $turn.WebSearchQueries += $msg.WebSearchQueries
                $turn.Citations        += $msg.Citations
                $turn.LastUtc           = $msg.CreatedUtc
            }
        }
        if ($turn) { $turns.Add($turn) }
    }

    if ($skippedNoJson.Count -gt 0) {
        Write-Host "Skipped $($skippedNoJson.Count) rendered-card file(s) with no per-message JSON: $($skippedNoJson -join ', ')" -ForegroundColor DarkGray
    }
    Write-Host "Assembled $($turns.Count) conversation turn(s) from $($htmlFiles.Count) file(s)." -ForegroundColor Cyan

    # De-duplicate on message identity only.
    #
    # A turn is a genuine duplicate only when the very same message was exported more than once
    # (same ConversationId AND same prompt message ItemId). Two threads can legitimately hold
    # byte-identical prompt text - a user re-asking the same question starts a new conversation -
    # and collapsing those on topic+text would silently delete real, reportable activity.
    $deduped = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($t in ($turns | Sort-Object PromptUtc)) {
        $key = '{0}|{1}' -f $t.ConversationId, $t.ItemId
        if (-not $key.Trim('|')) { $key = [guid]::NewGuid().ToString() }  # no identity -> never merge
        $respLen = (($t.ResponseText) -join '').Length
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $t
            $deduped.Add($t)
        }
        elseif ($respLen -gt ((($seen[$key].ResponseText) -join '').Length)) {
            $deduped[$deduped.IndexOf($seen[$key])] = $t
            $seen[$key] = $t
        }
    }
    if ($turns.Count -ne $deduped.Count) {
        Write-Host "Collapsed $($turns.Count - $deduped.Count) re-exported copy/copies of the same message." -ForegroundColor Yellow
    }

    $inRange = New-Object System.Collections.Generic.List[object]
    $outOfRange = 0
    foreach ($t in $deduped) {
        $whenUtc = [datetimeoffset]$t.PromptUtc
        if ($whenUtc -lt [datetimeoffset]::new($StartUtc) -or $whenUtc -ge [datetimeoffset]::new($EndUtc)) {
            $outOfRange++
            continue
        }
        $t | Add-Member -NotePropertyName WhenUtc -NotePropertyValue $whenUtc -Force
        $inRange.Add($t)
    }
    if ($outOfRange -gt 0) {
        Write-Host "Excluded $outOfRange turn(s) outside $($StartUtc.ToString('yyyy-MM-dd')) .. $($EndUtc.ToString('yyyy-MM-dd')) UTC." -ForegroundColor Yellow
    }

    return [pscustomobject]@{ Turns = $inRange; RawMessages = $rawMessages }
}

# ---- Main ----
if (-not (Test-Path $ExportPath)) { Write-Error "Export path not found: $ExportPath" }

# Check for TeamsMessagesData folder (native message export format)
$teamsPath = Get-ChildItem -Path $ExportPath -Filter 'TeamsMessagesData' -Recurse -Directory -ErrorAction SilentlyContinue | Select-Object -First 1

if ($teamsPath) {
    # Native format export with HTML message bodies
    Write-Host "✓ Found TeamsMessagesData folder - using native message format" -ForegroundColor Green
    $ExportPath = $teamsPath.Parent.FullName
    $parsed = Import-CopilotChatHtmlExport -Path $ExportPath -StartUtc $StartUtc -EndUtc $EndUtc
} else {
    # CSV-only export fallback - extract Copilot items from Items CSV
    Write-Host "⚠ TeamsMessagesData not found - using CSV metadata fallback" -ForegroundColor Yellow
    
    # Look for Items CSV in both root and Items subfolder
    $itemsCsv = @(
        Get-ChildItem -Path $ExportPath -Filter 'Items_*.csv' -ErrorAction SilentlyContinue |  Select-Object -First 1
        Get-ChildItem -Path $ExportPath -Filter 'Items' -Directory -ErrorAction SilentlyContinue | Get-ChildItem -Filter 'Items_*.csv' -ErrorAction SilentlyContinue | Select-Object -First 1
    ) | Where-Object { $_ } | Select-Object -First 1
    
    if (-not $itemsCsv) { 
        Write-Error "Neither TeamsMessagesData folder nor Items CSV found in export path: $ExportPath" 
    }

    
    Write-Host "✓ Loading Items CSV: $(Split-Path $itemsCsv -Leaf)" -ForegroundColor Cyan
    $allItems = @(Import-Csv $itemsCsv.FullName)
    
    # Filter for Copilot chat items
    $copilotItems = @($allItems | Where-Object { $_."Item Class" -like "*Copilot*" })
    Write-Host "✓ Found $($copilotItems.Count) Copilot items in export" -ForegroundColor Cyan
    
    # Convert CSV items to turns
    $turns = New-Object System.Collections.Generic.List[object]
    $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId)
    
    foreach ($item in $copilotItems) {
        $timestamp = $null
        
        # Try Date field first, then Received
        $dateStr = "$($item.'Date')".Trim()
        if ([string]::IsNullOrEmpty($dateStr)) {
            $dateStr = "$($item.'Received')".Trim()
        }
        
        if (-not [string]::IsNullOrEmpty($dateStr)) {
            try {
                # Parse as UTC 
                $timestamp = [datetime]::Parse($dateStr, [System.Globalization.CultureInfo]::InvariantCulture)
                if ($timestamp.Kind -ne [System.DateTimeKind]::Utc) {
                    $timestamp = [datetime]::SpecifyKind($timestamp, [System.DateTimeKind]::Utc)
                }
            } catch {
                Write-Verbose "Could not parse timestamp '$dateStr' for item"
                $timestamp = $null
            }
        }
        
        if ($null -eq $timestamp) { continue }  # Skip items without valid timestamps
        
        # Determine entrypoint from ItemClass
        $entrypoint = if ($item."Item class" -like "*BizChat*") {
            "Copilot Chat in Outlook/Teams (Bizchat)"
        } elseif ($item."Item class" -like "*WebChat*") {
            "Copilot Chat web URL (m365.cloud.microsoft/chat)"
        } else {
            "Copilot Chat (type not determined)"
        }
        
        $whoUtc = [datetimeoffset]::new($timestamp, [timespan]::Zero)
        
        # Check date range
        if ($whoUtc -lt [datetimeoffset]::new($StartUtc) -or $whoUtc -ge [datetimeoffset]::new($EndUtc)) {
            continue
        }

        
        # Extract actor from Sender or Email recipients
        $actor = "$($item.'Sender')".Trim()
        if ([string]::IsNullOrEmpty($actor)) {
            $actor = "$($item.'Email recipients')".Trim()
        }
        if ([string]::IsNullOrEmpty($actor)) {
            $actor = "$($item.'To')".Trim()
        }
        
        # Extract all fields before hash table (to avoid parsing issues)
        $convName = "$($item.'Conversation name')".Trim()
        $msgId = "$($item.'Internet message ID')".Trim()
        $convIdx = "$($item.'Conversation index')".Trim()
        $immId = "$($item.'Immutable ID')".Trim()
        $itemClass = $item.'Item class'
        
        $turns.Add([pscustomobject]@{
            Timestamp             = $timestamp.ToString('yyyy-MM-dd HH:mm:ss')
            TimestampUtc          = $whoUtc.UtcDateTime.ToString('o')
            WhenUtc               = $whoUtc
            Actor                 = $actor
            PromptSender          = $actor
            Conversation          = $convName
            ConversationId        = $msgId
            ThreadId              = $convIdx
            PromptText            = "⚠ Content not available in CSV-only export. Download native format export from Purview to see actual prompts."
            ResponseText          = @()
            Attachments           = @()
            WebSearchQueries      = @()
            Citations             = @()
            ItemId                = $immId
            SourceFile            = (Split-Path $itemsCsv.FullName -Leaf)
            CopilotEntrypoint     = $entrypoint
            AppIdentity           = if ($itemClass -like "*BizChat*") { "Copilot.M365Copilot.Bizchat" } else { "Copilot.M365Copilot.WebChat" }
            AppHost               = if ($itemClass -like "*BizChat*") { "BizChat" } else { "Web" }
        })

    }
    
    Write-Host "✓ Converted $($turns.Count) Copilot items to audit rows" -ForegroundColor Green
    
    $parsed = [pscustomobject]@{
        Turns = $turns
        RawMessages = @()
    }
}


New-Item -ItemType Directory -Path $OutputFolder -Force -ErrorAction SilentlyContinue | Out-Null

if (-not $teamsPath) {
    # CSV path already created $parsed, just need timezone
    $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId)
} else {
    # Native format path
    $parsed = Import-CopilotChatHtmlExport -Path $ExportPath -StartUtc $StartUtc -EndUtc $EndUtc
    $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId)
}

$auditEvents = @()
$auditByConversation = @{}
$auditByThread = @{}
if ($AuditEventsPath) {
    $auditEvents = Import-CopilotAuditEvents -Path $AuditEventsPath
    foreach ($a in $auditEvents) {
        if ($a.ConversationId) {
            if (-not $auditByConversation.ContainsKey($a.ConversationId)) {
                $auditByConversation[$a.ConversationId] = New-Object System.Collections.Generic.List[object]
            }
            $auditByConversation[$a.ConversationId].Add($a)
        }
        if ($a.ThreadId) {
            if (-not $auditByThread.ContainsKey($a.ThreadId)) {
                $auditByThread[$a.ThreadId] = New-Object System.Collections.Generic.List[object]
            }
            $auditByThread[$a.ThreadId].Add($a)
        }
    }
    Write-Host "Loaded $($auditEvents.Count) audit event(s) for optional entrypoint enrichment." -ForegroundColor Cyan
}

$rows = foreach ($t in $parsed.Turns) {
    $localTime = [System.TimeZoneInfo]::ConvertTime($t.WhenUtc, $tz)
    $queries   = @($t.WebSearchQueries | Where-Object { $_ } | Select-Object -Unique)
    $citations = @($t.Citations | Where-Object { $_ } | Group-Object Url | ForEach-Object { $_.Group[0] })
    $attach    = @($t.Attachments | Where-Object { $_ } | Select-Object -Unique)
    $actorEmail = Get-EmailFromDisplay -Value $t.PromptSender

    $auditMatch = $null
    $candidates = $null
    if ($auditByConversation.ContainsKey($t.ConversationId)) {
        $candidates = $auditByConversation[$t.ConversationId].ToArray()
    } elseif ($auditByThread.ContainsKey($t.ThreadId)) {
        $candidates = $auditByThread[$t.ThreadId].ToArray()
    }
    if ($candidates) {
        if ($actorEmail) {
            $actorMatched = @($candidates | Where-Object { -not $_.ActorEmail -or $_.ActorEmail -eq $actorEmail })
            if ($actorMatched.Count -gt 0) { $candidates = $actorMatched }
        }
        $auditMatch = $candidates | Sort-Object {
            if (-not $_.TimestampUtc) { return 1e12 }
            return [math]::Abs((($_.TimestampUtc) - $t.WhenUtc).TotalSeconds)
        } | Select-Object -First 1
    }
    $appIdentity = if ($auditMatch) { $auditMatch.AppIdentity } else { $t.AppIdentity }
    $appHost = if ($auditMatch) { $auditMatch.AppHost } else { $t.AppHost }
    $entrypoint = if ($auditMatch) {
        Resolve-CopilotEntrypoint -AppIdentity $auditMatch.AppIdentity -AppHost $auditMatch.AppHost
    } else {
        # Use the entrypoint already set during CSV parsing if available
        if ($t.CopilotEntrypoint) { $t.CopilotEntrypoint } else { $null }
    }

    [pscustomobject]@{
        Timestamp        = $localTime.ToString('yyyy-MM-dd HH:mm:ss K')
        TimestampUtc     = $t.WhenUtc.UtcDateTime.ToString('o')
        Actor            = $t.PromptSender
        Conversation     = $t.Topic
        ConversationId   = $t.ConversationId
        PromptText       = $t.PromptText
        ResponseText     = (($t.ResponseText | Where-Object { $_ }) -join "`n`n")
        Attachments      = ($attach -join '; ')
        WebSearchUsed    = if ($queries.Count -gt 0) { 'Yes' } else { 'No' }
        WebSearchKeywords = ($queries -join ' | ')
        CitationCount    = $citations.Count
        CitationURLs     = (($citations | Select-Object -ExpandProperty Url) -join '; ')
        AppIdentity      = $appIdentity
        AppHost          = $appHost
        CopilotEntrypoint = $entrypoint
        SourceFile       = (Split-Path $t.SourceFile -Leaf)
    }
}

$csvPath  = Join-Path $OutputFolder 'CopilotChat-ComplianceReport.csv'
$jsonPath = Join-Path $OutputFolder 'CopilotChat-ComplianceReport.json'
$rawPath  = Join-Path $OutputFolder 'CopilotChat-RawMessages.json'
$htmlPath = Join-Path $OutputFolder 'CopilotChat-ComplianceReport.html'

function Save-ReportFile {
    # A previous report left open in Excel holds an exclusive lock. Fail with an actionable
    # message rather than a raw IO exception, and never lose the run's output.
    param ([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][scriptblock]$Write)
    try { & $Write $Path }
    catch [System.IO.IOException] {
        $alt = [IO.Path]::Combine((Split-Path $Path), ('{0}-{1}{2}' -f
            [IO.Path]::GetFileNameWithoutExtension($Path), (Get-Date -Format 'yyyyMMdd-HHmmss'), [IO.Path]::GetExtension($Path)))
        Write-Warning "$(Split-Path $Path -Leaf) is locked (open in Excel?). Writing to $(Split-Path $alt -Leaf) instead."
        & $Write $alt
    }
}

Save-ReportFile -Path $csvPath -Write { param($p) $rows | Export-Csv -Path $p -NoTypeInformation -Encoding UTF8 }

# Full-fidelity turn objects: nothing truncated, arrays kept as arrays.
$detailed = foreach ($t in $parsed.Turns) {
    $actorEmail = Get-EmailFromDisplay -Value $t.PromptSender
    $auditMatch = $null
    $candidates = $null
    if ($auditByConversation.ContainsKey($t.ConversationId)) {
        $candidates = $auditByConversation[$t.ConversationId].ToArray()
    } elseif ($auditByThread.ContainsKey($t.ThreadId)) {
        $candidates = $auditByThread[$t.ThreadId].ToArray()
    }
    if ($candidates) {
        if ($actorEmail) {
            $actorMatched = @($candidates | Where-Object { -not $_.ActorEmail -or $_.ActorEmail -eq $actorEmail })
            if ($actorMatched.Count -gt 0) { $candidates = $actorMatched }
        }
        $auditMatch = $candidates | Sort-Object {
            if (-not $_.TimestampUtc) { return 1e12 }
            return [math]::Abs((($_.TimestampUtc) - $t.WhenUtc).TotalSeconds)
        } | Select-Object -First 1
    }

    [pscustomobject]@{
        TimestampUtc      = $t.WhenUtc.UtcDateTime.ToString('o')
        TimestampLocal    = ([System.TimeZoneInfo]::ConvertTime($t.WhenUtc, $tz)).ToString('yyyy-MM-dd HH:mm:ss K')
        TimeZone          = $TimeZoneId
        Actor             = $t.PromptSender
        Conversation      = $t.Topic
        ConversationId    = $t.ConversationId
        ThreadId          = $t.ThreadId
        PromptItemId      = $t.ItemId
        PromptText        = $t.PromptText
        ResponseText      = @($t.ResponseText | Where-Object { $_ })
        Attachments       = @($t.Attachments | Where-Object { $_ } | Select-Object -Unique)
        WebSearchKeywords = @($t.WebSearchQueries | Where-Object { $_ } | Select-Object -Unique)
        Citations         = @($t.Citations | Where-Object { $_ } | Group-Object Url | ForEach-Object { $_.Group[0] })
        AuditMetadata     = if ($auditMatch) {
            [pscustomobject]@{
                AppIdentity      = $auditMatch.AppIdentity
                AppHost          = $auditMatch.AppHost
                CopilotEntrypoint = (Resolve-CopilotEntrypoint -AppIdentity $auditMatch.AppIdentity -AppHost $auditMatch.AppHost)
                AuditTimestampUtc = if ($auditMatch.TimestampUtc) { $auditMatch.TimestampUtc.UtcDateTime.ToString('o') } else { $null }
                MatchMethod       = 'ConversationId + nearest timestamp (+ actor when available)'
            }
        } else { $null }
        SourceFile        = (Split-Path $t.SourceFile -Leaf)
        FieldProvenance   = [pscustomobject]@{
            PromptText        = 'ItemData.content  (message where ItemData.messageFrom starts "8:orgid:")'
            ResponseText      = 'ItemData.content  (message where ItemData.messageFrom starts "28:"); base64 SWIFT/AdaptiveCard decoded when present'
            WebSearchKeywords = 'LinksBlob[] -> entries with "@type":"WebSearchQuery" -> url = queries=["..."]'
            Citations         = 'LinksBlob[] -> entries with "@type":"CITATION" -> url / linkMetadata.providerDisplayName'
            Attachments       = 'ItemData.properties -> copilotMetadata.messageAnnotations[] where messageAnnotationType = "LocalFile"'
            TimestampUtc      = 'CreatedDateTime (top-level, regex-read from raw JSON text)'
            ConversationId    = 'CopilotConversationId (top-level)'
            AppIdentity       = 'Unified audit payload (AuditData.AppIdentity)'
            AppHost           = 'Unified audit payload (AuditData.AppHost)'
            CopilotEntrypoint = 'Derived from AppIdentity + AppHost mapping table in RUNBOOK.md'
        }
    }
}
Save-ReportFile -Path $jsonPath -Write { param($p) $detailed | ConvertTo-Json -Depth 8 | Set-Content -Path $p -Encoding UTF8 }
Save-ReportFile -Path $rawPath  -Write { param($p) $parsed.RawMessages | ConvertTo-Json -Depth 8 | Set-Content -Path $p -Encoding UTF8 }

$generatedLocal = [System.TimeZoneInfo]::ConvertTime([datetimeoffset]::UtcNow, $tz).ToString('yyyy-MM-dd HH:mm:ss K')
$actorCount = @($rows.Actor | Where-Object { $_ } | Select-Object -Unique).Count
$threadCount = @($rows.ConversationId | Where-Object { $_ } | Select-Object -Unique).Count
$webCount = @($rows | Where-Object { $_.WebSearchUsed -eq 'Yes' }).Count
$attachCount = @($rows | Where-Object { $_.Attachments }).Count
$entryCount = @($rows | Where-Object { $_.CopilotEntrypoint }).Count

$tableRows = foreach ($r in $rows) {
    $keywords = if ($r.WebSearchKeywords) { "<span class='chip web'>$(ConvertTo-HtmlEncoded $r.WebSearchKeywords)</span>" } else { "<span class='muted'>No web search recorded</span>" }
    $attachmentsHtml = if ($r.Attachments) { "<span class='chip file'>$(ConvertTo-HtmlEncoded $r.Attachments)</span>" } else { "<span class='muted'>None</span>" }
    $entryHtml = if ($r.CopilotEntrypoint) { ConvertTo-HtmlEncoded $r.CopilotEntrypoint } else { "<span class='muted'>Not supplied - run with -AuditEventsPath</span>" }
    @"
<tr data-actor="$(ConvertTo-HtmlEncoded $r.Actor)" data-web="$($r.WebSearchUsed)" data-entry="$(ConvertTo-HtmlEncoded $r.CopilotEntrypoint)">
  <td class="ts">$(ConvertTo-HtmlEncoded $r.Timestamp)<br><span class="muted">$(ConvertTo-HtmlEncoded $r.TimestampUtc)</span></td>
  <td>$(ConvertTo-HtmlEncoded $r.Actor)</td>
  <td><strong>$(ConvertTo-HtmlEncoded $r.Conversation)</strong><br><span class="mono">$(ConvertTo-HtmlEncoded $r.ConversationId)</span></td>
  <td>$entryHtml<br><span class="mono">AppIdentity: $(ConvertTo-HtmlEncoded $r.AppIdentity)<br>AppHost: $(ConvertTo-HtmlEncoded $r.AppHost)</span></td>
  <td><div class="body">$(ConvertTo-HtmlEncoded $r.PromptText)</div></td>
  <td><div class="body">$(ConvertTo-HtmlEncoded $r.ResponseText)</div></td>
  <td>$attachmentsHtml</td>
  <td>$keywords</td>
  <td class="cites">$(ConvertTo-HtmlEncoded $r.CitationURLs)</td>
  <td class="src">$(ConvertTo-HtmlEncoded $r.SourceFile)</td>
</tr>
"@
}

$html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Copilot Chat Compliance Report</title>
<style>
  :root { --bd:#d0d7de; --mut:#656d76; --acc:#0969da; --bg:#f6f8fa; --ok:#1a7f37; --warn:#9a6700; }
  * { box-sizing:border-box; }
  body { margin:0; font-family:'Segoe UI',system-ui,-apple-system,sans-serif; background:var(--bg); color:#24292f; }
  header { padding:20px 28px; background:#fff; border-bottom:1px solid var(--bd); }
  h1 { margin:0 0 6px; font-size:22px; }
  .sub { color:var(--mut); font-size:13px; line-height:1.5; }
  .cards { display:flex; gap:12px; flex-wrap:wrap; padding:18px 28px 0; }
  .card { min-width:145px; background:#fff; border:1px solid var(--bd); border-radius:8px; padding:12px 14px; }
  .v { color:var(--acc); font-size:24px; font-weight:700; }
  .k { color:var(--mut); font-size:11px; text-transform:uppercase; letter-spacing:.05em; }
  .note { margin:16px 28px 0; padding:12px 14px; border:1px solid #f0d48a; background:#fff8c5; border-radius:8px; font-size:13px; line-height:1.5; }
  .controls { padding:16px 28px 8px; display:flex; gap:10px; flex-wrap:wrap; }
  input,select { padding:7px 9px; border:1px solid var(--bd); border-radius:6px; font-family:inherit; font-size:13px; }
  #q { min-width:360px; }
  .wrap { padding:8px 28px 32px; overflow:auto; }
  table { width:100%; border-collapse:collapse; background:#fff; font-size:12px; }
  th,td { border:1px solid var(--bd); padding:8px; text-align:left; vertical-align:top; }
  th { background:#f3f4f6; position:sticky; top:0; z-index:1; white-space:nowrap; }
  tr:nth-child(even) td { background:#fbfbfb; }
  tr.hide { display:none; }
  .body { max-height:180px; min-width:260px; max-width:520px; overflow:auto; white-space:pre-wrap; }
  .mono { font-family:Consolas,monospace; font-size:11px; color:var(--mut); word-break:break-all; }
  .muted { color:var(--mut); font-style:italic; }
  .chip { display:inline-block; border-radius:999px; padding:3px 8px; margin:1px; font-size:11px; }
  .chip.web { background:#fff1e5; border:1px solid #ffd8b5; color:#8a4600; }
  .chip.file { background:#ddf4ff; border:1px solid #b6e3ff; color:#0969da; }
  .cites { max-width:300px; word-break:break-all; }
  .src { max-width:180px; color:var(--mut); word-break:break-all; }
  footer { padding:0 28px 36px; color:var(--mut); font-size:12px; line-height:1.5; }
</style>
</head>
<body>
<header>
  <h1>Copilot Chat Compliance Report</h1>
  <div class="sub">
    <div>Review window UTC: $(ConvertTo-HtmlEncoded $StartUtc.ToString('o')) to $(ConvertTo-HtmlEncoded $EndUtc.ToString('o'))</div>
    <div>Display timezone: $(ConvertTo-HtmlEncoded $TimeZoneId)</div>
    <div>Generated: $(ConvertTo-HtmlEncoded $generatedLocal)</div>
  </div>
</header>
<section class="cards">
  <div class="card"><div class="v">$($rows.Count)</div><div class="k">Turns</div></div>
  <div class="card"><div class="v">$actorCount</div><div class="k">Actors</div></div>
  <div class="card"><div class="v">$threadCount</div><div class="k">Threads</div></div>
  <div class="card"><div class="v">$webCount</div><div class="k">Web search</div></div>
  <div class="card"><div class="v">$attachCount</div><div class="k">Attachments</div></div>
  <div class="card"><div class="v">$entryCount</div><div class="k">Entrypoint mapped</div></div>
</section>
"@

if (-not $AuditEventsPath) {
    $html += @"
<div class="note"><strong>Entrypoint fields are not populated in this run.</strong> The eDiscovery export contains prompt/response content, but the host entrypoint lives in the CopilotInteraction audit payload. Re-run with <code>-AuditEventsPath</code> to fill AppIdentity, AppHost, and CopilotEntrypoint.</div>
"@
}

$html += @"
<section class="controls">
  <input id="q" type="search" placeholder="Filter by actor, conversation, prompt, response, keyword, citation...">
  <select id="fWeb"><option value="">All web states</option><option value="Yes">Used web search</option><option value="No">No web search</option></select>
  <select id="fEntry"><option value="">All entrypoints</option></select>
</section>
<main class="wrap">
<table id="report">
  <thead>
    <tr>
      <th>Timestamp</th><th>Actor</th><th>Conversation</th><th>Entrypoint</th><th>Prompt</th><th>Response</th><th>Attachments</th><th>Web Search Keywords</th><th>Citations</th><th>Source</th>
    </tr>
  </thead>
  <tbody>
    $($tableRows -join "`n")
  </tbody>
</table>
</main>
<footer>
  Entrypoint mapping comes from audit fields: <code>AuditData.AppIdentity</code>, <code>AuditData.CopilotEventData.AppHost</code>, and <code>AuditData.CopilotEventData.ConversationId</code>. Prompt and response content comes from the eDiscovery transcript export.
</footer>
<script>
const q = document.getElementById('q');
const fWeb = document.getElementById('fWeb');
const fEntry = document.getElementById('fEntry');
const rows = [...document.querySelectorAll('#report tbody tr')];
const entries = [...new Set(rows.map(r => r.dataset.entry).filter(Boolean))].sort();
for (const e of entries) {
  const o = document.createElement('option');
  o.value = e; o.textContent = e; fEntry.appendChild(o);
}
function applyFilters() {
  const needle = q.value.toLowerCase();
  const web = fWeb.value;
  const entry = fEntry.value;
  for (const r of rows) {
    const text = r.innerText.toLowerCase();
    const show = (!needle || text.includes(needle)) &&
                 (!web || r.dataset.web === web) &&
                 (!entry || r.dataset.entry === entry);
    r.classList.toggle('hide', !show);
  }
}
q.addEventListener('input', applyFilters);
fWeb.addEventListener('change', applyFilters);
fEntry.addEventListener('change', applyFilters);
</script>
</body>
</html>
"@

Save-ReportFile -Path $htmlPath -Write { param($p) Set-Content -Path $p -Value $html -Encoding UTF8 }

$withSearch = @($rows | Where-Object { $_.WebSearchUsed -eq 'Yes' }).Count
$withAttach = @($rows | Where-Object { $_.Attachments }).Count
$withEntrypoint = @($rows | Where-Object { $_.CopilotEntrypoint }).Count

Write-Host ''
Write-Host "Report generated" -ForegroundColor Green
Write-Host "  CSV  : $csvPath"
Write-Host "  JSON : $jsonPath   (full fidelity, per turn)"
Write-Host "  RAW  : $rawPath    (per message, for field-level searching)"
Write-Host "  HTML : $htmlPath   (interactive reviewer report)"
Write-Host ''
Write-Host "  Turns in range     : $($rows.Count)"
Write-Host "  Distinct threads   : $(@($rows.ConversationId | Select-Object -Unique).Count)"
Write-Host "  Actors             : $(@($rows.Actor | Select-Object -Unique).Count)"
Write-Host "  Used web search    : $withSearch"
Write-Host "  Had attachments    : $withAttach"
Write-Host "  Entrypoint mapped  : $withEntrypoint"
Write-Host "  Messages captured  : $($parsed.RawMessages.Count)"
