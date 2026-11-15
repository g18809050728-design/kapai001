param([switch]$Verify, [switch]$Capture)
$ErrorActionPreference = 'Stop'
$polishRoot = Split-Path -Parent $PSScriptRoot
$polishArguments = @('--path', $polishRoot, '--script', 'res://tools/run_actor_rig_pilot.gd', '--', '--polished')
if ($Verify) { $polishArguments += '--verify' }
if ($Capture) { $polishArguments += '--capture' }
& 'F:/GoDot/Godot_v4.7.2-stable_win64_console.exe' @polishArguments
exit $LASTEXITCODE
