param([switch]$Verify, [switch]$Capture)
$ErrorActionPreference = 'Stop'
$refinementRoot = Split-Path -Parent $PSScriptRoot
$refinementArguments = @('--path', $refinementRoot, '--script', 'res://tools/run_actor_rig_pilot.gd', '--', '--refinement')
if ($Verify) { $refinementArguments += '--verify' }
if ($Capture) { $refinementArguments += '--capture' }
& 'F:/GoDot/Godot_v4.7.2-stable_win64_console.exe' @refinementArguments
exit $LASTEXITCODE
