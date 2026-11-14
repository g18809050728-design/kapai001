param([Parameter(Mandatory=$true)][string]$Name,
      [ValidateSet('generate','edit','batch')][string]$Mode='generate',
      [string]$InputImage='', [string]$Size='1536x1024', [switch]$DryRun)
$ErrorActionPreference = 'Stop'
$pilotRoot = Split-Path -Parent $PSScriptRoot
$pilotOutput = Join-Path $pilotRoot 'output/imagegen/actor-rig-pilot-20261114'
$pilotConfig = Get-Content -LiteralPath 'C:/Users/Dev.LI/.codex/imagegen/config.json' -Raw -Encoding UTF8 | ConvertFrom-Json
$pilotPrompt = Join-Path $pilotOutput ($Name + '.prompt.txt')
$pilotImage = Join-Path $pilotOutput ($Name + '.png')
$pilotEvidence = Join-Path $pilotRoot 'artifacts/verification/actor-rig-pilot-20261114'
if ($Mode -eq 'batch') {
    $pilotJobs = Join-Path $pilotOutput ($Name + '.jobs.jsonl')
    if (-not (Test-Path -LiteralPath $pilotJobs)) { throw 'Missing batch jobs.' }
    $pilotArgs = @('generate-batch','--input',$pilotJobs,'--out-dir',$pilotOutput,'--model',$pilotConfig.model,'--concurrency','2','--max-attempts','1','--fail-fast')
} else {
    if (-not (Test-Path -LiteralPath $pilotPrompt)) { throw 'Missing named prompt.' }
    if (Test-Path -LiteralPath $pilotImage) { throw 'Retain existing image; use a new name.' }
    $pilotArgs = @($Mode,'--model',$pilotConfig.model,'--prompt-file',$pilotPrompt,'--size',$Size,'--quality','medium','--out',$pilotImage)
    if ($Mode -eq 'edit') { $pilotArgs += @('--image',$InputImage) }
}
if ($DryRun) {
    $ErrorActionPreference = 'Continue'
    & $pilotConfig.python $pilotConfig.cli_script @pilotArgs --dry-run 2>&1 | Tee-Object -FilePath (Join-Path $pilotEvidence ($Name + '.dry-run.log'))
    exit $LASTEXITCODE
}
$pilotSavedKey = $env:OPENAI_API_KEY
$pilotSavedBase = $env:OPENAI_BASE_URL
$pilotSavedError = $ErrorActionPreference
$pilotSecureKey = ConvertTo-SecureString -String ([IO.File]::ReadAllText($pilotConfig.credential_file))
$pilotKeyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pilotSecureKey)
try {
    $env:OPENAI_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pilotKeyPointer)
    $env:OPENAI_BASE_URL = $pilotConfig.base_url
    $ErrorActionPreference = 'Continue'
    & $pilotConfig.python $pilotConfig.cli_script @pilotArgs 2>&1 | ForEach-Object { $_.ToString().Replace($env:OPENAI_API_KEY, '[REDACTED]') } | Tee-Object -FilePath (Join-Path $pilotEvidence ($Name + '.generation.log'))
    $pilotExitCode = $LASTEXITCODE
} finally {
    $env:OPENAI_API_KEY = $pilotSavedKey
    $env:OPENAI_BASE_URL = $pilotSavedBase
    $ErrorActionPreference = $pilotSavedError
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pilotKeyPointer)
}
@{model=$pilotConfig.model;provider=$pilotConfig.base_url;size=$Size;mode=$Mode;quality='medium';exit_code=$pilotExitCode;prompt=$pilotPrompt;image=$pilotImage;completed_utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $pilotEvidence ($Name + '.generation.json')) -Encoding UTF8
if ($pilotExitCode -ne 0) { throw "Image generation failed: $pilotExitCode" }
