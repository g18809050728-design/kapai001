param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = 'Stop'
if (-not $GodotPath) {
    $candidates = @('F:\GoDot\Godot_v4.7.2-stable_win64_console.exe','D:\chrome\godot\Godot_v4.7.2-stable_win64_console.exe')
    $GodotPath = ($candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
    if (-not $GodotPath) { $GodotPath = (Get-Command godot -ErrorAction Stop).Source }
}
$repo = Split-Path $PSScriptRoot -Parent
& $GodotPath --path $repo -- --relic-pilot
exit $LASTEXITCODE
