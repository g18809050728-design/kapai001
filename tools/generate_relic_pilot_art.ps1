param(
    [string]$Batch = 'jobs.jsonl',
    [ValidateSet('relic-pilot-20261120','relic-roster-20261120')][string]$ProjectBatch = 'relic-pilot-20261120',
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$cfg = Get-Content -LiteralPath "$HOME/.codex/imagegen/config.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$dir = Join-Path $repo "output/imagegen/$ProjectBatch"
$job = Join-Path $dir $Batch
if (-not (Test-Path -LiteralPath $job -PathType Leaf)) { throw "Job list not found: $job" }
$concurrency = if ($cfg.workflow.batch_concurrency) { $cfg.workflow.batch_concurrency } else { 2 }
$argsForCli = @($cfg.cli_script, 'generate-batch', '--input', $job, '--out-dir', (Join-Path $dir 'raw'),
    '--model', $cfg.model, '--concurrency', $concurrency, '--max-attempts', 1, '--fail-fast', '--no-augment')
if ($DryRun) {
    & $cfg.python @argsForCli --dry-run
    exit $LASTEXITCODE
}
$savedKey = $env:OPENAI_API_KEY
$savedEndpoint = $env:OPENAI_BASE_URL
$secure = ConvertTo-SecureString -String ([IO.File]::ReadAllText($cfg.credential_file))
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $env:OPENAI_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    $env:OPENAI_BASE_URL = $cfg.base_url
    $env:PYTHONIOENCODING = 'utf-8'
    $ErrorActionPreference = 'Continue'
    & $cfg.python @argsForCli 2>&1 | ForEach-Object { $_.ToString().Replace($env:OPENAI_API_KEY, '[REDACTED]') }
    $status = $LASTEXITCODE
} finally {
    $env:OPENAI_API_KEY = $savedKey
    $env:OPENAI_BASE_URL = $savedEndpoint
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
}
exit $status
