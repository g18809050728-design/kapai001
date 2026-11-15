param([switch]$Verify, [switch]$Capture)
$ErrorActionPreference = 'Stop'
$actorProject = Split-Path -Parent $PSScriptRoot
$actorEngine = 'F:/GoDot/Godot_v4.7.2-stable_win64_console.exe'
$actorArguments = @('--path', $actorProject, '--script', 'res://tools/run_actor_rig_pilot.gd', '--', '--seams')
if ($Verify) { $actorArguments += '--verify' }
if ($Capture) { $actorArguments += '--capture' }
& $actorEngine @actorArguments
exit $LASTEXITCODE
