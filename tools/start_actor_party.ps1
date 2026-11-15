param(
    [ValidateSet('P01', 'P02', 'P03', 'P04')][string]$Character = 'P04',
    [ValidateSet('V11', 'V10', 'V9', 'V8', 'V7')][string]$Version = 'V11',
    [switch]$Verify,
    [switch]$Capture
)
$ErrorActionPreference = 'Stop'
$actorProject = Split-Path -Parent $PSScriptRoot
$actorEngine = 'F:/GoDot/Godot_v4.7.2-stable_win64_console.exe'
$actorPilot = switch ($Version) {
    'V7' { 'res://tools/run_actor_party_pilot.gd' }
    'V8' { 'res://tools/run_actor_proportions_pilot.gd' }
    'V9' { 'res://tools/run_actor_posture_pilot.gd' }
    'V10' { 'res://tools/run_actor_rebuild_pilot.gd' }
    'V11' { 'res://tools/run_actor_motion_pilot.gd' }
}
$actorArguments = @('--path', $actorProject, '--script', $actorPilot, '--', "--character=$Character")
if ($Verify) { $actorArguments += '--verify' }
if ($Capture) { $actorArguments += '--capture' }
& $actorEngine @actorArguments
exit $LASTEXITCODE
