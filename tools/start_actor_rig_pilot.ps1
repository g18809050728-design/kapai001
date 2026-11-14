param([switch]$Verify, [switch]$Capture)
$ErrorActionPreference = 'Stop'
$pilotRoot = Split-Path -Parent $PSScriptRoot
$pilotArguments = @('--path', $pilotRoot, '--script', 'res://tools/run_actor_rig_pilot.gd')
if ($Verify -or $Capture) {
    $pilotArguments += '--'
    if ($Verify) { $pilotArguments += '--verify' }
    if ($Capture) { $pilotArguments += '--capture' }
}
& 'F:/GoDot/Godot_v4.7.2-stable_win64_console.exe' @pilotArguments
exit $LASTEXITCODE
