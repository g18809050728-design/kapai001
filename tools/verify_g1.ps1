param(
	[string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$runId = "g1-" + (Get-Date -Format "yyyyMMdd-HHmmss-fff") + "-" + [guid]::NewGuid().ToString("N").Substring(0, 6)
$evidenceDir = Join-Path $projectRoot (Join-Path "artifacts/verification" $runId)
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
$expectedVersion = "4.7.2.stable"
$started = (Get-Date).ToString("o")
$env:PYTHONUTF8 = "1"
$godotProblem = $null
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
	$installedConsole = $null
	foreach ($candidate in @(
		'D:\Godot\Godot_v4.7.2-stable_win64_console.exe',
		'F:\GoDot\Godot_v4.7.2-stable_win64_console.exe',
		'C:\Godot\Godot_v4.7.2-stable_win64_console.exe'
	)) {
		if (Test-Path -LiteralPath $candidate -PathType Leaf) {
			$installedConsole = $candidate
			break
		}
	}
	$godotCommand = Get-Command godot -ErrorAction SilentlyContinue
	if (-not [string]::IsNullOrEmpty($installedConsole)) {
		$GodotPath = $installedConsole
	} elseif ($null -ne $godotCommand) {
		$GodotPath = $godotCommand.Source
	} else {
		$godotProblem = "Godot 4.7.2 is required. Set GODOT_BIN or pass -GodotPath."
	}
}
if (-not $godotProblem -and -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
	$godotProblem = "Godot executable not found: $GodotPath"
}

function Invoke-RecordedCommand {
	param([string]$Name, [string[]]$Arguments, [int]$ExpectedExitCode = 0)
	$stdoutPath = Join-Path $evidenceDir "$Name.stdout.txt"
	$stderrPath = Join-Path $evidenceDir "$Name.stderr.txt"
	$argumentLine = ($Arguments | ForEach-Object {
		$builder = [System.Text.StringBuilder]::new()
		[void]$builder.Append('"')
		$backslashes = 0
		for ($index = 0; $index -lt $_.Length; $index++) {
			$character = $_[$index]
			if ($character -eq '\') {
				$backslashes++
				continue
			}
			if ($character -eq '"') {
				[void]$builder.Append(('\' * (($backslashes * 2) + 1)))
				[void]$builder.Append('"')
			} else {
				if ($backslashes -gt 0) {
					[void]$builder.Append(('\' * $backslashes))
				}
				[void]$builder.Append($character)
			}
			$backslashes = 0
		}
		if ($backslashes -gt 0) {
			[void]$builder.Append(('\' * ($backslashes * 2)))
		}
		[void]$builder.Append('"')
		$builder.ToString()
	}) -join " "
	$process = Start-Process -FilePath $script:CommandExecutable -ArgumentList $argumentLine `
		-WorkingDirectory $projectRoot -RedirectStandardOutput $stdoutPath `
		-RedirectStandardError $stderrPath -PassThru -Wait -NoNewWindow
	$exitCode = $process.ExitCode
	[System.IO.File]::WriteAllText((Join-Path $evidenceDir "$Name.exit_code.txt"), "$exitCode`n", [System.Text.UTF8Encoding]::new($false))
	if ($exitCode -ne $ExpectedExitCode) {
		throw "$Name returned exit code $exitCode; expected $ExpectedExitCode. See $evidenceDir"
	}
}

if ($godotProblem) {
	$versionExit = 127
	$actualVersion = "unavailable"
	$versionOutput = @()
	[System.IO.File]::WriteAllText((Join-Path $evidenceDir "engine_version.stdout.txt"), "", [System.Text.UTF8Encoding]::new($false))
	[System.IO.File]::WriteAllText((Join-Path $evidenceDir "engine_version.stderr.txt"), "$godotProblem`n", [System.Text.UTF8Encoding]::new($false))
} else {
	$script:CommandExecutable = $GodotPath
	$versionInvocationFailure = $null
	try {
		Invoke-RecordedCommand -Name "engine_version" -Arguments @("--version")
	} catch {
		$versionInvocationFailure = $_.Exception.Message
	}
	$versionCodePath = Join-Path $evidenceDir "engine_version.exit_code.txt"
	$versionExit = if (Test-Path -LiteralPath $versionCodePath) { [int](Get-Content -Raw $versionCodePath) } else { 127 }
	$actualVersion = (Get-Content -Raw -Encoding UTF8 (Join-Path $evidenceDir "engine_version.stdout.txt")).Trim()
}
$versionInvocationFailure = if ($godotProblem) { $godotProblem } else { $versionInvocationFailure }
$environment = [ordered]@{
	engine = $actualVersion
	engine_executable = if ($GodotPath) { $GodotPath } else { "not found" }
	os = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
	process_architecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
	powershell = $PSVersionTable.PSVersion.ToString()
	python = (& python --version 2>&1 | Out-String).Trim()
	gdformat = "checked by format_check command"
	cwd = $projectRoot
	started = $started
}
[System.IO.File]::WriteAllText((Join-Path $evidenceDir "environment.json"), ($environment | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))

$commands = @(
	[ordered]@{ name = "engine_version"; executable = $GodotPath; arguments = @("--version") },
	[ordered]@{ name = "editor_import"; executable = $GodotPath; arguments = @("--headless", "--editor", "--path", $projectRoot, "--quit") },
	[ordered]@{ name = "headless_tests"; executable = $GodotPath; arguments = @("--headless", "--path", $projectRoot, "--script", "res://tests/run_tests.gd") },
	[ordered]@{ name = "test_failure_probe"; executable = $GodotPath; arguments = @("--headless", "--path", $projectRoot, "--script", "res://tests/run_tests.gd", "--", "--force-failure"); expected_exit = 1 },
	[ordered]@{ name = "headless_startup"; executable = $GodotPath; arguments = @("--headless", "--path", $projectRoot, "--quit-after", "2") }
)
$script:CommandExecutable = $GodotPath
$allPassed = $false
$failure = $null
try {
	if ($godotProblem) {
		throw $godotProblem
	}
	if ($versionInvocationFailure) {
		throw $versionInvocationFailure
	}
	$versionMatches = $actualVersion -eq $expectedVersion -or $actualVersion.StartsWith("$expectedVersion.")
	if ($versionExit -ne 0 -or -not $versionMatches) {
		throw "Expected Godot $expectedVersion, found '$actualVersion'."
	}
	$script:CommandExecutable = $GodotPath
	foreach ($command in $commands | Where-Object { $_.name -ne "engine_version" }) {
		$expectedExit = if ($command.Contains("expected_exit")) { $command.expected_exit } else { 0 }
		Invoke-RecordedCommand -Name $command.name -Arguments $command.arguments -ExpectedExitCode $expectedExit
	}
	$script:CommandExecutable = (Get-Command gdformat -ErrorAction Stop).Source
	Invoke-RecordedCommand -Name "format_check" -Arguments @("--check", "src", "tests") -ExpectedExitCode 0
	$allPassed = $true
} catch {
	$failure = $_.Exception.Message
}

$trackedInputs = @(
	"project.godot", "README.md", "实施计划与验收基线.md", "docs/接口文档.md",
	"docs/初步架构设计.md", "src", "tests", "tools/verify_g1.ps1",
	"requirements-dev.txt", ".editorconfig", ".github/workflows/godot.yml"
)
$inputHashes = [ordered]@{}
foreach ($item in $trackedInputs) {
	$path = Join-Path $projectRoot $item
	if (Test-Path -LiteralPath $path -PathType Leaf) {
		$inputHashes[$item] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
	} elseif (Test-Path -LiteralPath $path -PathType Container) {
		$rootPrefix = $projectRoot.TrimEnd('\') + '\'
		Get-ChildItem -LiteralPath $path -File -Recurse | Sort-Object FullName | ForEach-Object {
			$relative = $_.FullName.Substring($rootPrefix.Length).Replace("\", "/")
			$inputHashes[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
		}
	}
}
[System.IO.File]::WriteAllText((Join-Path $evidenceDir "inputs.json"), ($inputHashes | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $evidenceDir "command.json"), (@($commands) + @([ordered]@{ name = "format_check"; executable = "gdformat"; arguments = @("--check", "src", "tests"); expected_exit = 0 }) | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $evidenceDir "report.json"), ([ordered]@{ stage = "G1"; status = $(if ($allPassed) { "passed" } else { "failed" }); expected_godot = $expectedVersion; actual_godot = $actualVersion; failure = $failure; checks = $(if ($allPassed) { 5 } else { "incomplete" }) } | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
$reportLines = @("# G1 verification", "", "- Run ID: ``$runId``", "- Godot: ``$actualVersion``", "- Status: $(if ($allPassed) { "passed" } else { "failed" })", "- Failure: $(if ($failure) { $failure } else { "none" })", "- Started: ``$started``")
[System.IO.File]::WriteAllLines((Join-Path $evidenceDir "report.md"), $reportLines, [System.Text.UTF8Encoding]::new($false))
$resultCode = if ($allPassed) { 0 } else { 1 }
[System.IO.File]::WriteAllText((Join-Path $evidenceDir "exit_code.txt"), "$resultCode`n", [System.Text.UTF8Encoding]::new($false))
Write-Output "G1 status: $(if ($allPassed) { "passed" } else { "failed" })"
Write-Output "Evidence: $evidenceDir"
if ($failure) { Write-Error $failure }
exit $resultCode
