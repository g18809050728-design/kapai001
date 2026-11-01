param(
	[string]$GodotPath = $env:GODOT_BIN,
	[ValidatePattern("^g5-[A-Za-z0-9-]+$")]
	[string]$RunId = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = "g5-" + (Get-Date -Format "yyyyMMdd-HHmmss-fff") + "-" + [guid]::NewGuid().ToString("N").Substring(0, 6) }
$evidenceDir = Join-Path $projectRoot (Join-Path "artifacts/verification" $runId)
if (Test-Path -LiteralPath $evidenceDir) { throw "Evidence directory already exists: $evidenceDir" }
New-Item -ItemType Directory -Path $evidenceDir | Out-Null
$started = (Get-Date).ToString("o")
$expectedVersion = "4.7.2.stable"
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
	param([string]$Name, [string[]]$Arguments, [string]$Executable, [int]$ExpectedExitCode = 0)
	$stdoutPath = Join-Path $evidenceDir "$Name.stdout.txt"
	$stderrPath = Join-Path $evidenceDir "$Name.stderr.txt"
	$argumentLine = ($Arguments | ForEach-Object {
		$builder = [System.Text.StringBuilder]::new()
		[void]$builder.Append('"')
		$backslashes = 0
		for ($index = 0; $index -lt $_.Length; $index++) {
			$character = $_[$index]
			if ($character -eq '\') { $backslashes++; continue }
			if ($character -eq '"') {
				[void]$builder.Append(('\' * (($backslashes * 2) + 1)))
				[void]$builder.Append('"')
			} else {
				if ($backslashes -gt 0) { [void]$builder.Append(('\' * $backslashes)) }
				[void]$builder.Append($character)
			}
			$backslashes = 0
		}
		if ($backslashes -gt 0) { [void]$builder.Append(('\' * ($backslashes * 2))) }
		[void]$builder.Append('"')
		$builder.ToString()
	}) -join " "
	$process = Start-Process -FilePath $Executable -ArgumentList $argumentLine `
		-WorkingDirectory $projectRoot -RedirectStandardOutput $stdoutPath `
		-RedirectStandardError $stderrPath -PassThru -Wait -NoNewWindow
	$exitCode = $process.ExitCode
	[System.IO.File]::WriteAllText((Join-Path $evidenceDir "$Name.exit_code.txt"), "$exitCode`n", [System.Text.UTF8Encoding]::new($false))
	if ($exitCode -ne $ExpectedExitCode) {
		throw "$Name returned exit code $exitCode; expected $ExpectedExitCode. See $evidenceDir"
	}
	if ($Name -in @("headless_tests", "editor_import")) {
		$log = (Get-Content -Raw -Encoding UTF8 $stdoutPath) + (Get-Content -Raw -Encoding UTF8 $stderrPath)
		if ($log -match "SCRIPT ERROR|Parse Error|GDScript backtrace") {
			throw "$Name reported a Godot script error despite its process exit code. See $evidenceDir"
		}
	}
    if ($Name -eq "headless_tests" -and $log -notmatch "G5 headless tests passed") {
        throw "G5 success marker missing. See $evidenceDir"
    }
}

$python = (Get-Command python -ErrorAction Stop).Source
$gdformat = (Get-Command gdformat -ErrorAction Stop).Source
$deferredPath = Join-Path $projectRoot "data/manifests/content_deferred.json"
$deferredData = Get-Content -Raw -Encoding UTF8 $deferredPath | ConvertFrom-Json
$holdbackCount = 0
foreach ($property in $deferredData.manifest_holdback.PSObject.Properties) {
	$holdbackCount += @($property.Value).Count
}
$commands = @(
	[ordered]@{ name = "static_manifest_audit"; executable = $python; arguments = @("tools/verify_g2.py") },
	[ordered]@{ name = "editor_import"; executable = $GodotPath; arguments = @("--headless", "--editor", "--path", $projectRoot, "--quit") },
	[ordered]@{ name = "headless_tests"; executable = $GodotPath; arguments = @("--headless", "--path", $projectRoot, "--script", "res://tests/run_tests.gd") },
	[ordered]@{ name = "evidence_check"; executable = $python; arguments = @("tools/check_g5_evidence.py", $evidenceDir) },
	[ordered]@{ name = "format_check"; executable = $gdformat; arguments = @("--check", "src", "tests") }
)
$environment = [ordered]@{
	engine = "unavailable"
	engine_executable = if ($GodotPath) { $GodotPath } else { "not found" }
	os = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
	process_architecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
	powershell = $PSVersionTable.PSVersion.ToString()
	python = (& $python --version 2>&1 | Out-String).Trim()
	gdformat = (& $gdformat --version 2>&1 | Out-String).Trim()
	cwd = $projectRoot
	started = $started
}
$allPassed = $false
$failure = $godotProblem
try {
	if ($godotProblem) { throw $godotProblem }
	Invoke-RecordedCommand -Name "engine_version" -Executable $GodotPath -Arguments @("--version")
	$actualVersion = (Get-Content -Raw -Encoding UTF8 (Join-Path $evidenceDir "engine_version.stdout.txt")).Trim()
	$environment.engine = $actualVersion
	if (-not ($actualVersion -eq $expectedVersion -or $actualVersion.StartsWith("$expectedVersion."))) {
		throw "Expected Godot $expectedVersion, found '$actualVersion'."
	}
	[System.IO.File]::WriteAllText((Join-Path $evidenceDir "environment.json"), ($environment | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
	foreach ($command in $commands) {
		Invoke-RecordedCommand -Name $command.name -Executable $command.executable -Arguments $command.arguments
	}
	if ($holdbackCount -ne 0) { throw "Production manifest has $holdbackCount holdback definitions" }
    $allPassed = $true
} catch {
	$failure = $_.Exception.Message
}

$trackedInputs = @(
    "project.godot", "src", "tests", "data", "docs/baselines/g0.json",
    "docs/局流程契约.md", "docs/接口文档.md", "docs/数据库与实体关系设计.md",
    "docs/战斗模块契约.md", "tools/verify_g2.py", "tools/verify_g5.ps1", "tools/check_g5_evidence.py"
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
[System.IO.File]::WriteAllText((Join-Path $evidenceDir "command.json"), (@([ordered]@{ name = "engine_version"; executable = $GodotPath; arguments = @("--version") }) + @($commands) | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
$stageStatus = if ($allPassed -and $holdbackCount -eq 0) { "passed" } else { "failed" }
[System.IO.File]::WriteAllText((Join-Path $evidenceDir "report.json"), ([ordered]@{ stage = "G5"; verification = $(if ($allPassed) { "passed" } else { "failed" }); stage_status = $stageStatus; holdback_count = $holdbackCount; failure = $failure; godot = $environment.engine } | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
$reportLines = @("# G5 verification", "", "- Run ID: ``$runId``", "- Verification: $(if ($allPassed) { "passed" } else { "failed" })", "- Stage status: $stageStatus", "- Production holdback definitions: $holdbackCount", "- Godot: ``$($environment.engine)``", "- Failure: $(if ($failure) { $failure } else { "none" })", "- Started: ``$started``")
[System.IO.File]::WriteAllLines((Join-Path $evidenceDir "report.md"), $reportLines, [System.Text.UTF8Encoding]::new($false))
$resultCode = if ($allPassed) { 0 } else { 1 }
[System.IO.File]::WriteAllText((Join-Path $evidenceDir "exit_code.txt"), "$resultCode`n", [System.Text.UTF8Encoding]::new($false))
Write-Output "G5 verification: $(if ($allPassed) { "passed" } else { "failed" })"
Write-Output "G5 stage: $stageStatus ($holdbackCount production definitions remain in holdback)"
Write-Output "Evidence: $evidenceDir"
if ($failure) { Write-Error $failure }
exit $resultCode
