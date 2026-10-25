[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$probeDirectory = Join-Path $env:TEMP "github-copilot-model-probe-$([guid]::NewGuid())"

try {
    New-Item -ItemType Directory -Path $probeDirectory | Out-Null

    & copilot --log-dir $probeDirectory --log-level debug `
        --model '__model_catalog_probe__' -p 'catalog probe' --output-format json *> $null

    $log = Get-ChildItem -LiteralPath $probeDirectory -File -Filter '*.log' |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $log) {
        throw 'GitHub Copilot CLI did not create a probe log.'
    }

    $event = Select-String -LiteralPath $log.FullName `
        -Pattern '\[rust:capi_models\] fetched model catalog from CAPI' |
        Select-Object -Last 1 -ExpandProperty Line

    if (-not $event) {
        throw 'GitHub Copilot CLI did not record a CAPI model catalog event.'
    }

    $metadata = $event.Substring($event.IndexOf('{')) | ConvertFrom-Json
    $catalog = $metadata.models | ConvertFrom-Json
    $models = $catalog |
        Where-Object {
            $_.model_picker_enabled -eq $true -and
            $_.policy.state -eq 'enabled'
        } |
        ForEach-Object {
            [ordered]@{
                id = $_.id
                name = $_.name
                category = $_.model_picker_category
                preview = [bool]$_.preview
                contextWindow = $_.capabilities.limits.max_context_window_tokens
                reasoningEffort = @($_.capabilities.supports.reasoning_effort)
            }
        }

    [ordered]@{
        checkedAt = (Get-Date).ToString('o')
        source = 'GitHub Copilot CLI CAPI catalog'
        models = @($models)
    } | ConvertTo-Json -Depth 5
}
finally {
    if (Test-Path -LiteralPath $probeDirectory) {
        Remove-Item -LiteralPath $probeDirectory -Recurse -Force
    }
}
