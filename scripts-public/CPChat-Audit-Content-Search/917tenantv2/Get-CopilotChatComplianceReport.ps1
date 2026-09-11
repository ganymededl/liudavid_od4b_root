<#
.SYNOPSIS
    Builds a Copilot Chat compliance report from a Standard eDiscovery export.

.DESCRIPTION
    Standard eDiscovery exports message content in PST files and optional search metadata
    in Items_*.csv. This script can read the PSTs alone and uses the CSV when present. It does not require eDiscovery Premium,
    HTML transcript export, or a tenant connection.

    The script intentionally stops with an error when no message body can be read;
    it never presents metadata-only rows as prompts or responses.

.PARAMETER ExportPath
    Extracted export folder containing PST/Exchange/*.pst and, optionally, Items_*.csv.

.PARAMETER OutputFolder
    Folder for the HTML, CSV, and JSON reports.

.PARAMETER StartUtc
    Inclusive UTC start. Defaults to seven days before now.

.PARAMETER EndUtc
    Exclusive UTC end. Defaults to now.

.PARAMETER TimeZoneId
    Windows time zone used for display timestamps.

.EXAMPLE
    .\Get-CopilotChatComplianceReport.ps1 `
      -ExportPath 'C:\CopilotAudit\Input' `
      -OutputFolder 'C:\CopilotAudit\Report' `
      -StartUtc ([datetime]'2026-09-04T00:00:00Z') `
      -EndUtc ([datetime]'2026-09-07T00:00:00Z') `
      -TimeZoneId 'Eastern Standard Time'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$ExportPath,
    [Parameter(Mandatory)] [string]$OutputFolder,
    [datetime]$StartUtc = (Get-Date).ToUniversalTime().AddDays(-7),
    [datetime]$EndUtc = (Get-Date).ToUniversalTime(),
    [string]$TimeZoneId = 'UTC'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ExportPath -PathType Container)) {
    throw "ExportPath does not exist: $ExportPath"
}
$tz = [TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId)
$start = [DateTimeOffset]$StartUtc.ToUniversalTime()
$end = [DateTimeOffset]$EndUtc.ToUniversalTime()
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null

function Get-Text([object]$value) {
    if ($null -eq $value) { return '' }
    return ([string]$value).Trim()
}
function Html([object]$value) {
    return [System.Net.WebUtility]::HtmlEncode((Get-Text $value))
}
function Get-RowValue([object]$row, [string[]]$names) {
    foreach ($name in $names) {
        $property = $row.PSObject.Properties | Where-Object Name -eq $name | Select-Object -First 1
        if ($property) {
            $value = Get-Text $property.Value
            if ($value) { return $value }
        }
    }
    return ''
}
function Add-TextNodes([object]$node, [System.Collections.Generic.List[string]]$sink) {
    if ($null -eq $node) { return }
    if ($node -is [string]) { return }
    if ($node -is [System.Collections.IEnumerable]) {
        foreach ($child in $node) { Add-TextNodes $child $sink }
        return
    }
    foreach ($property in $node.PSObject.Properties) {
        if ($property.Name -eq 'text' -and $property.Value -is [string]) {
            [void]$sink.Add($property.Value)
        } else {
            Add-TextNodes $property.Value $sink
        }
    }
}
$script:FileRefPattern = '(?<name>[^\s<>"]+\.(?:txt|csv|log|json|xml|docx|doc|xlsx|xls|pptx|ppt|potx|pdf|png|jpg|jpeg|gif|zip|msg|eml))\s*<(?<url>[^>]+)>'
function Get-NormalizedUrl([string]$url) {
    # Copilot appends a per-reference tracking id, so strip it before comparing.
    $normalized = [regex]::Replace($url, '(?i)[?&]EntityRepresentationId=[^&]*', '')
    return $normalized.TrimEnd('&', '?')
}
function Get-UserAttachments([object]$item) {
    # A file the user uploaded arrives as a message whose plain body is nothing
    # but file references. Grounded tenant files appear inside answer prose instead.
    $plain = Get-Text $item.Body
    if (-not $plain) { return @() }
    $matches = [regex]::Matches($plain, $script:FileRefPattern)
    if ($matches.Count -eq 0) { return @() }
    $remainder = [regex]::Replace($plain, $script:FileRefPattern, '')
    $remainder = [regex]::Replace($remainder, 'unknown-file-name\s*<[^>]*>', '')
    if ($remainder.Trim()) { return @() }
    return @($matches | ForEach-Object { "$($_.Groups['name'].Value) <$($_.Groups['url'].Value)>" })
}
function Get-Body([object]$item) {
    $plain = Get-Text $item.Body
    $html = Get-Text $item.HTMLBody

    # Copilot answers ride in a base64 adaptive card. The plain body of an
    # attachment turn holds only the file reference, so always inspect both.
    $cardText = ''
    foreach ($candidate in @($html, $plain)) {
        if ($candidate -match '(?is)<Swift\s+b64="([^"]+)"') {
            try {
                $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Matches[1]))
                $payload = $decoded | ConvertFrom-Json
                $textParts = New-Object System.Collections.Generic.List[string]
                Add-TextNodes $payload $textParts
                if ($textParts.Count -gt 0) {
                    $cardText = $textParts -join "`n`n"
                    break
                }
            } catch [FormatException] {
                # Preserve the original exported body when the card encoding is invalid.
            } catch [System.Management.Automation.RuntimeException] {
                # Preserve the original exported body when the card payload is not JSON.
            }
        }
    }

    $body = $plain
    if (-not $body) { $body = $html }
    if ($cardText) {
        if ($plain -and $plain -notmatch '(?is)<Swift\s+b64=') {
            $body = "$plain`n`n$cardText"
        } else {
            $body = $cardText
        }
    }

    if ($body -match '(?is)<body[^>]*>(.*?)</body>') {
        $body = [regex]::Replace($Matches[1], '(?is)<br\s*/?>', "`n")
        $body = [regex]::Replace($body, '(?is)<[^>]+>', '')
        $body = [System.Net.WebUtility]::HtmlDecode($body)
    }
    return $body.Trim()
}
function Get-Folders([object]$folder) {
    Write-Output $folder
    foreach ($child in @($folder.Folders)) {
        Get-Folders $child
    }
}
function Complete-Row([System.Collections.Specialized.OrderedDictionary]$row) {
    $response = [string]$row.Response
    $attachments = @([string]$row.Attachments -split "`n" | Where-Object { $_ })

    # File references inside answer prose are tenant sources Copilot grounded on.
    $fileUrls = New-Object System.Collections.Generic.List[string]
    $grounded = New-Object System.Collections.Generic.List[string]
    foreach ($match in [regex]::Matches($response, $script:FileRefPattern)) {
        $entry = "$($match.Groups['name'].Value) <$($match.Groups['url'].Value)>"
        [void]$fileUrls.Add($match.Groups['url'].Value)
        if ($attachments -notcontains $entry -and -not $grounded.Contains($entry)) {
            [void]$grounded.Add($entry)
        }
    }
    foreach ($entry in $attachments) {
        if ($entry -match '<(?<url>[^>]+)>') { [void]$fileUrls.Add($Matches['url']) }
    }

    # Copilot reports its search terms in a fenced block under a bold or heading label.
    $keywordPattern = '(?is)(?:\*\*|#{1,6}\s*)[^\n]*?\bsearch\s+(?:terms|keywords|queries)\b[^\n]*?\r?\n+\s*```(?:text)?\s*(?<terms>.*?)```'
    if ($response -match $keywordPattern) {
        $row.WebSearchKeywords = $Matches['terms'].Trim()
    } elseif ($response -match '(?is)(?:following|exact)[^\n]*?\b(?:bing-style\s+)?(?:search\s+)?(?:keywords|queries)\b[^\n]*?\r?\n+\s*```(?:text)?\s*(?<terms>.*?)```') {
        $row.WebSearchKeywords = $Matches['terms'].Trim()
    }

    # Copilot marks every cited source inline as a bracketed reference token. These
    # cover internal files as well as web pages, so they alone do not prove a web search.
    $row.SourceRefs = ([regex]::Matches($response, '\u3010[^\u3011]*\u3011') | ForEach-Object { $_.Value } | Sort-Object -Unique).Count

    # Citations are external web sources. Tenant links are grounding references.
    $internalHostPattern = '(?i)^https?://[^/]*(\.sharepoint\.com|outlook\.office365?\.com|outlook\.office\.com|teams\.microsoft\.com)(/|$)'
    $normalizedFileUrls = @($fileUrls | ForEach-Object { Get-NormalizedUrl $_ })
    $citations = New-Object System.Collections.Generic.List[string]
    foreach ($match in [regex]::Matches($response, 'https?://[^\s<>"\)\]]+')) {
        $url = $match.Value.TrimEnd('.', ',', ';')
        $normalized = Get-NormalizedUrl $url
        if ($normalizedFileUrls -contains $normalized) { continue }
        if ($url -match $internalHostPattern) {
            $entry = "internal item <$url>"
            if (-not $grounded.Contains($entry)) { [void]$grounded.Add($entry) }
            continue
        }
        if (-not $citations.Contains($url)) { [void]$citations.Add($url) }
    }
    $row.GroundedFiles = $grounded -join "`n"
    $row.Citations = ($citations | Sort-Object -Unique) -join "`n"

    # Copilot emits a "Searching..." status when it queries the public web, and the
    # export preserves it. That status, reported keywords, or an external citation each
    # independently prove the turn left the tenant.
    $searched = ($response -match '(?im)^\s*Searching\.\.\.') -or
                [bool]$row.WebSearchKeywords -or
                $citations.Count -gt 0
    $row.WebSearchUsed = if ($searched) { 'Yes' } else { 'No' }

    [pscustomobject]$row
}

$itemsCsv = Get-ChildItem -LiteralPath $ExportPath -Filter 'Items_*.csv' -Recurse -File |
    Sort-Object FullName | Select-Object -First 1
$metadata = @()
if ($itemsCsv) {
    $metadata = @(Import-Csv -LiteralPath $itemsCsv.FullName |
        Where-Object { (Get-RowValue $_ @('Item class','Item Class')) -like '*Copilot*' })
}

$metadataByKey = @{}
foreach ($row in $metadata) {
    $id = Get-RowValue $row @('Internet message ID','Immutable ID')
    if ($id) { $metadataByKey[$id] = $row }
}

$pstFiles = Get-ChildItem -LiteralPath $ExportPath -Filter '*.pst' -Recurse -File
if (-not $pstFiles) { throw "No PST files were found below $ExportPath. Standard export content is missing." }

$out = New-Object System.Collections.Generic.List[object]
$openedStores = New-Object System.Collections.Generic.List[object]
$outlook = New-Object -ComObject Outlook.Application
$namespace = $outlook.GetNameSpace('MAPI')
try { $namespace.Logon('', '', $false, $false) } catch { Write-Host "MAPI logon reused existing session." -ForegroundColor DarkGray }

$staleNames = $pstFiles | ForEach-Object { $_.BaseName }
foreach ($existing in @($namespace.Folders)) {
    if ($staleNames -contains $existing.Name) {
        Write-Host "Removing stale store left by a previous run: $($existing.Name)" -ForegroundColor DarkYellow
        try { $namespace.RemoveStore($existing) } catch { }
    }
}
try {
    foreach ($pst in $pstFiles) {
        Write-Host "Reading PST: $($pst.Name)" -ForegroundColor Cyan
        $namespace.AddStore($pst.FullName)
        $store = @($namespace.Folders | Where-Object {
            $_.Name -eq $pst.Name -or $_.Name -like "$($pst.BaseName)*"
        } | Select-Object -Last 1)
        if (-not $store) { throw "Outlook could not open PST: $($pst.FullName)" }
        foreach ($folder in @(Get-Folders $store[0])) {
            if ($folder.Name -ne 'TeamsMessagesData') { continue }
            Write-Host "  Scanning folder: $($folder.Name)" -ForegroundColor DarkCyan
            $pending = $null
            $folderItems = @($folder.Items) | Sort-Object ReceivedTime
            Write-Host "    Items in folder: $($folderItems.Count)" -ForegroundColor DarkGray
            $itemIndex = 0
            foreach ($item in $folderItems) {
                $itemIndex++
                Write-Host "    [$itemIndex/$($folderItems.Count)] reading item" -ForegroundColor DarkGray
                $body = Get-Body $item
                if (-not $body) { continue }
                $received = $null
                try { $received = [DateTimeOffset]::new([datetime]$item.ReceivedTime) } catch { continue }
                if ($received -lt $start -or $received -ge $end) { continue }
                $sender = Get-Text $item.SenderName
                $class = Get-Text $item.MessageClass
                $candidate = $null
                if ($metadata.Count -gt 0 -and -not $class) {
                    $receivedDay = $received.UtcDateTime.ToString('yyyy-MM-dd')
                    $candidate = $metadata | Where-Object {
                        (Get-RowValue $_ @('Date','Received')) -like "$receivedDay*"
                    } | Select-Object -First 1
                }
                if (-not $candidate -and $class -notlike '*Copilot*' -and $body -notmatch '(?i)copilot') { continue }
                if (-not $class -and $candidate) { $class = Get-RowValue $candidate @('Item class','Item Class') }
                if (-not $class) { $class = 'Copilot content identified from PST' }
                $actor = $pst.BaseName -replace '\.001$',''
                $local = [TimeZoneInfo]::ConvertTime($received, $tz)
                $entrypoint = if ($class -like '*BizChat*') { 'Outlook/Teams BizChat' } elseif ($class -like '*WebChat*') { 'Copilot Chat web' } else { 'Copilot Chat' }
                if ($body -match '(?is)^\s*\*\*prompt\s+(?<num>\d+)\*\*') {
                    if ($pending) { $out.Add((Complete-Row $pending)) }
                    $promptLabel = "prompt $($Matches['num'])"
                    $prompt = [regex]::Replace($body, '(?is)^\s*(\*\*prompt\s+\d+\*\*)\s*', '$1 ')
                    $pending = [ordered]@{
                        Timestamp = $local.ToString('yyyy-MM-dd HH:mm:ss zzz')
                        TimestampUtc = $received.UtcDateTime.ToString('o')
                        Actor = $actor
                        Entrypoint = $entrypoint
                        ItemClass = $class
                        PromptLabel = $promptLabel
                        Prompt = $prompt.Trim()
                        Response = ''
                        Attachments = ''
                        GroundedFiles = ''
                        WebSearchUsed = ''
                        WebSearchKeywords = ''
                        Citations = ''
                        SourceRefs = 0
                        SourcePst = $pst.Name
                        SourceFolder = $folder.Name
                    }
                } elseif ($pending) {
                    if ($pending.Response) { $pending.Response += "`n`n" }
                    $pending.Response += $body
                    foreach ($attachment in (Get-UserAttachments $item)) {
                        $existing = @([string]$pending.Attachments -split "`n" | Where-Object { $_ })
                        if ($existing -notcontains $attachment) {
                            if ($pending.Attachments) { $pending.Attachments += "`n" }
                            $pending.Attachments += $attachment
                        }
                    }
                } else {
                    $pending = [ordered]@{
                        Timestamp = $local.ToString('yyyy-MM-dd HH:mm:ss zzz')
                        TimestampUtc = $received.UtcDateTime.ToString('o')
                        Actor = $actor
                        Entrypoint = $entrypoint
                        ItemClass = $class
                        PromptLabel = 'unlabeled'
                        Prompt = $body.Trim()
                        Response = ''
                        Attachments = ''
                        GroundedFiles = ''
                        WebSearchUsed = ''
                        WebSearchKeywords = ''
                        Citations = ''
                        SourceRefs = 0
                        SourcePst = $pst.Name
                        SourceFolder = $folder.Name
                    }
                    foreach ($attachment in (Get-UserAttachments $item)) {
                        $pending.Attachments = $attachment
                    }
                }
            }
            if ($pending) { $out.Add((Complete-Row $pending)) }
        }
        Write-Host "  Finished reading: $($pst.Name)" -ForegroundColor DarkGreen
        $openedStores.Add($store[0])
    }
}
finally {
    Write-Host "Reading complete. Rows collected: $($out.Count)" -ForegroundColor Green
}

if ($out.Count -eq 0) {
    throw "No readable Copilot message bodies were found in the PSTs for the requested UTC window. The CSV is metadata-only; do not use it as a prompt/response report."
}

$csvPath = Join-Path $OutputFolder 'CopilotChat-ComplianceReport.csv'
$jsonPath = Join-Path $OutputFolder 'CopilotChat-ComplianceReport.json'
$htmlPath = Join-Path $OutputFolder 'CopilotChat-ComplianceReport.html'
$out | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
$out | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$actorOptions = (($out | Select-Object -ExpandProperty Actor -Unique | Sort-Object | ForEach-Object {
    "<option value='$(Html $_)'>$(Html $_)</option>"
}) -join '')
$displayZone = [TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId)
$startDisplay = [TimeZoneInfo]::ConvertTimeFromUtc($StartUtc.ToUniversalTime(), $displayZone).ToString('yyyy-MM-dd HH:mm:ss zzz')
$endDisplay = [TimeZoneInfo]::ConvertTimeFromUtc($EndUtc.ToUniversalTime(), $displayZone).ToString('yyyy-MM-dd HH:mm:ss zzz')
$generatedDisplay = [TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $displayZone).ToString('yyyy-MM-dd HH:mm:ss zzz')
$fileCount = @($out | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Attachments) }).Count
$groundedCount = @($out | Where-Object { -not [string]::IsNullOrWhiteSpace($_.GroundedFiles) }).Count
$webCount = @($out | Where-Object { $_.WebSearchUsed -eq 'Yes' }).Count
$table = foreach ($row in $out) {
    $hasFiles = -not [string]::IsNullOrWhiteSpace($row.Attachments)
    $hasWeb = $row.WebSearchUsed -eq 'Yes'
    $class = if ($hasWeb) { 'web-yes' } else { 'web-no' }
    "<tr data-actor='$(Html $row.Actor)' data-web='$hasWeb' data-files='$hasFiles'><td class='num'>$(Html $row.PromptLabel)</td><td class='ts'>$(Html $row.Timestamp)<br><small>$(Html $row.TimestampUtc)</small></td><td>$(Html $row.Actor)</td><td>$(Html $row.Entrypoint)</td><td class='body'><div class='clamp'><pre>$(Html $row.Prompt)</pre></div></td><td class='body'><div class='clamp'><pre>$(Html $row.Response)</pre></div></td><td class='files'>$(Html $row.Attachments)</td><td>$(Html $row.GroundedFiles)</td><td class='$class'>$(Html $row.WebSearchUsed)</td><td>$(Html $row.WebSearchKeywords)</td><td class='cites'>$(Html $row.Citations)</td><td>$(Html $row.SourceRefs)</td><td class='src'>$(Html $row.SourcePst)</td></tr>"
}
$html = @"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Copilot Chat Compliance Report</title>
<style>
:root{--bd:#d8dee4;--mut:#66717b;--acc:#0f6cbd;--bg:#f7f9fb;--ink:#1f2933}
*{box-sizing:border-box}body{font-family:"Segoe UI",Arial,sans-serif;margin:0;background:var(--bg);color:var(--ink)}
header{background:#fff;border-bottom:1px solid var(--bd);padding:22px 28px}h1{margin:0 0 6px;font-size:22px;font-weight:600}.sub{color:var(--mut);font-size:13px;line-height:1.55}
.cards{display:flex;gap:12px;flex-wrap:wrap;padding:18px 28px 0}.card{background:#fff;border:1px solid var(--bd);border-radius:6px;padding:12px 16px;min-width:132px}.card .v{font-size:23px;font-weight:600;color:var(--acc)}.card .k{font-size:11px;color:var(--mut);text-transform:uppercase;letter-spacing:.35px;margin-top:3px}
.note{margin:16px 28px 0;padding:12px 16px;border-radius:6px;font-size:13px;line-height:1.5}.note.ok{background:#f0f9f0;border:1px solid #b7e0b7}.note.warn{background:#fff8e6;border:1px solid #f0d48a}
.controls{padding:17px 28px 9px;display:flex;gap:10px;flex-wrap:wrap;align-items:center}input,select,button{padding:8px 10px;border:1px solid var(--bd);border-radius:4px;font-size:13px;font-family:inherit;background:#fff}input#q{min-width:330px}button{cursor:pointer}button:hover{background:#eef3f7}#count{color:var(--mut);font-size:13px}
.wrap{padding:8px 28px 42px;overflow-x:auto}table{border-collapse:collapse;width:100%;background:#fff;font-size:13px}th,td{border:1px solid var(--bd);padding:8px 10px;text-align:left;vertical-align:top}th{background:#eef2f5;position:sticky;top:0;font-weight:600;white-space:nowrap;z-index:2}td.num{color:var(--mut);white-space:nowrap}td.ts{white-space:nowrap;font-variant-numeric:tabular-nums}td.body{max-width:430px}pre{white-space:pre-wrap;min-width:220px;margin:0;font:inherit}.clamp{max-height:125px;overflow:auto;white-space:pre-wrap}td.cites{max-width:270px;word-break:break-all;font-size:11px}td.src{font-size:11px;color:var(--mut);max-width:210px}small{color:var(--mut)}td.web-yes{background:#fff1e5;color:#9a3412;font-weight:600;text-align:center}td.web-no{color:var(--mut);text-align:center}tr:nth-child(even) td{background:#fcfcfc}tr.hide{display:none}.muted{color:var(--mut);font-style:italic}
footer{padding:0 28px 40px;color:var(--mut);font-size:12px;line-height:1.6}
</style></head><body>
<header><h1>Copilot Chat Compliance Report</h1><div class="sub"><div>Review window: $(Html $startDisplay) to $(Html $endDisplay)</div><div>All timestamps shown in $(Html $TimeZoneId)</div><div>Generated: $(Html $generatedDisplay)</div><div>Rows with readable PST content: $($out.Count)</div></div></header>
<div class="cards"><div class="card"><div class="v">$($out.Count)</div><div class="k">Interactions</div></div><div class="card"><div class="v">$(@($out | Select-Object -ExpandProperty Actor -Unique).Count)</div><div class="k">Actors</div></div><div class="card"><div class="v">$fileCount</div><div class="k">With uploads</div></div><div class="card"><div class="v">$groundedCount</div><div class="k">With grounded files</div></div><div class="card"><div class="v">$webCount</div><div class="k">Used web search</div></div></div>
<div class="note ok"><strong>Evidence source:</strong> prompt and answer text are read from the exported PST messages. User uploads are listed separately from files Copilot referenced as grounding. Web-search status is derived from the exported response signals, keywords, or external citations.</div>
<div class="controls"><input id="q" type="search" placeholder="Filter prompt, answer, actor, file name..."><select id="fActor"><option value="">All actors</option>$actorOptions</select><select id="fFlag"><option value="">All interactions</option><option value="web">Used web search</option><option value="files">Has uploads</option></select><button onclick="expandAll()">Expand all text</button><button onclick="resetAll()">Reset filters</button><span id="count"></span></div>
<div class="wrap"><table id="t"><thead><tr><th>Prompt</th><th>Timestamp</th><th>Actor</th><th>Entrypoint</th><th>Prompt text</th><th>Copilot answer</th><th>Uploads</th><th>Grounded files</th><th>Web search</th><th>Search keywords</th><th>Citations</th><th>Source refs</th><th>Source PST</th></tr></thead><tbody>$($table -join "`n")</tbody></table></div>
<footer>Use the HTML for review, CSV for filtering and analysis, and JSON for structured evidence. The report contains only readable content present in the PST export.</footer>
<script>
const q=document.getElementById('q'),actor=document.getElementById('fActor'),flag=document.getElementById('fFlag'),count=document.getElementById('count');
function apply(){const query=q.value.toLowerCase(),a=actor.value,f=flag.value;let shown=0;document.querySelectorAll('#t tbody tr').forEach(r=>{const okText=!query||r.innerText.toLowerCase().includes(query),okActor=!a||r.dataset.actor===a,okFlag=!f||(f==='web'&&r.dataset.web==='True')||(f==='files'&&r.dataset.files==='True');const show=okText&&okActor&&okFlag;r.classList.toggle('hide',!show);if(show)shown++});count.textContent=shown+' of '+document.querySelectorAll('#t tbody tr').length+' rows shown'}
function expandAll(){document.querySelectorAll('.clamp').forEach(x=>x.style.maxHeight='none')}
function resetAll(){q.value='';actor.value='';flag.value='';document.querySelectorAll('.clamp').forEach(x=>x.style.maxHeight='');apply()}
[q,actor,flag].forEach(x=>x.addEventListener('input',apply));apply();
</script></body></html>
"@
Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8
Write-Host "Generated $($out.Count) content-bearing row(s)." -ForegroundColor Green
Write-Host "CSV:  $csvPath"
Write-Host "JSON: $jsonPath"
Write-Host "HTML: $htmlPath"

Write-Host "Detaching PST stores from the Outlook profile (report is already saved)." -ForegroundColor DarkGray
foreach ($store in $openedStores) {
    try { $namespace.RemoveStore($store) } catch { }
}
[void][Runtime.InteropServices.Marshal]::ReleaseComObject($namespace)
[void][Runtime.InteropServices.Marshal]::ReleaseComObject($outlook)
Write-Host "Done." -ForegroundColor Green
