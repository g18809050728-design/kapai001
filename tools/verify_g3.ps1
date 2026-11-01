param(
	[string]$GodotPath = $env:GODOT_BIN,
	[string]$Step = "G3-05"
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$runId = "g3-" + (Get-Date -Format "yyyyMMdd-HHmmss-fff") + "-" + [guid]::NewGuid().ToString("N").Substring(0, 6)
$evidenceDir = Join-Path $projectRoot (Join-Path "artifacts/verification" $runId)
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
$started = (Get-Date).ToString("o")
$expectedVersion = "4.7.2.stable"
$env:PYTHONUTF8 = "1"

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
		throw "Godot 4.7.2 is required. Set GODOT_BIN or pass -GodotPath."
	}
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
	throw "Godot executable not found: $GodotPath"
}

function ConvertTo-ArgumentLine {
	param([string[]]$Arguments)
	return (($Arguments | ForEach-Object {
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
	}) -join " ")
}

function Invoke-RecordedCommand {
	param([string]$Name, [string]$Executable, [string[]]$Arguments)
	$stdoutPath = Join-Path $evidenceDir "$Name.stdout.txt"
	$stderrPath = Join-Path $evidenceDir "$Name.stderr.txt"
	$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
	$startInfo.FileName = $Executable
	$startInfo.Arguments = ConvertTo-ArgumentLine $Arguments
	$startInfo.WorkingDirectory = $projectRoot
	$startInfo.UseShellExecute = $false
	$startInfo.RedirectStandardOutput = $true
	$startInfo.RedirectStandardError = $true
	$startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
	$startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
	$process = [System.Diagnostics.Process]::new()
	$process.StartInfo = $startInfo
	[void]$process.Start()
	$stdoutTask = $process.StandardOutput.ReadToEndAsync()
	$stderrTask = $process.StandardError.ReadToEndAsync()
	$process.WaitForExit()
	[System.IO.File]::WriteAllText($stdoutPath, $stdoutTask.Result, [System.Text.UTF8Encoding]::new($false))
	[System.IO.File]::WriteAllText($stderrPath, $stderrTask.Result, [System.Text.UTF8Encoding]::new($false))
	$exitCode = $process.ExitCode
	[System.IO.File]::WriteAllText((Join-Path $evidenceDir "$Name.exit_code.txt"), "$exitCode`n", [System.Text.UTF8Encoding]::new($false))
	if ($exitCode -ne 0) {
		throw "$Name returned exit code $exitCode. See $evidenceDir"
	}
	$log = (Get-Content -Raw -Encoding UTF8 $stdoutPath) + (Get-Content -Raw -Encoding UTF8 $stderrPath)
	if ($log -match "SCRIPT ERROR|Parse Error|GDScript backtrace") {
		throw "$Name reported a Godot script error despite exit code 0. See $evidenceDir"
	}
	return $log
}

$python = (Get-Command python -ErrorAction Stop).Source
$gdformatCommand = Get-Command gdformat -ErrorAction SilentlyContinue
$gdformat = if ($null -ne $gdformatCommand) { $gdformatCommand.Source } else { $null }
$deferred = Get-Content -Raw -Encoding UTF8 (Join-Path $projectRoot "data/manifests/content_deferred.json") | ConvertFrom-Json
$holdbackCount = 0
foreach ($property in $deferred.manifest_holdback.PSObject.Properties) {
	$holdbackCount += @($property.Value).Count
}
$g2StageStatus = "not_run"
$priorSteps = @("G3-01", "G3-02", "G3-03", "G3-04")
$priorStepEvidence = [ordered]@{}
if ($Step -eq "G3-05") {
	$verificationRoot = Join-Path $projectRoot "artifacts/verification"
	$priorRunDirectories = Get-ChildItem -LiteralPath $verificationRoot -Directory -Filter "g3-*" |
		Sort-Object LastWriteTime -Descending
	foreach ($directory in $priorRunDirectories) {
		$reportPath = Join-Path $directory.FullName "report.json"
		$exitPath = Join-Path $directory.FullName "exit_code.txt"
		if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf) -or
			-not (Test-Path -LiteralPath $exitPath -PathType Leaf)) {
			continue
		}
		try {
			$priorReport = Get-Content -Raw -Encoding UTF8 $reportPath | ConvertFrom-Json
			$priorExitCode = (Get-Content -Raw -Encoding UTF8 $exitPath).Trim()
			if ($priorReport.verification -eq "passed" -and $priorExitCode -eq "0" -and
				$priorSteps -contains $priorReport.step -and -not $priorStepEvidence.Contains($priorReport.step)) {
				$priorStepEvidence[$priorReport.step] = $directory.Name
			}
		} catch {
			continue
		}
	}
}
$missingPriorSteps = @($priorSteps | Where-Object { -not $priorStepEvidence.Contains($_) })

$formatCheck = if ($null -ne $gdformat) {
	[ordered]@{ name = "format_check"; executable = $gdformat; arguments = @("--check", "src", "tests") }
} else {
	[ordered]@{
		name = "format_check"
		executable = Join-Path $PSHOME "powershell.exe"
		arguments = @("-NoProfile", "-Command", "gdformat --check src tests")
	}
}
$commands = @(
	[ordered]@{ name = "python_version"; executable = $python; arguments = @("--version") },
	[ordered]@{ name = "document_audit"; executable = $python; arguments = @("tools/verify_g0.py") },
	[ordered]@{ name = "g2_static_audit"; executable = $python; arguments = @("tools/verify_g2.py") },
	[ordered]@{ name = "editor_import"; executable = $GodotPath; arguments = @("--headless", "--editor", "--path", $projectRoot, "--quit", "--log-file", (Join-Path $evidenceDir "godot_editor.log")) },
	[ordered]@{ name = "headless_tests"; executable = $GodotPath; arguments = @("--headless", "--path", $projectRoot, "--script", "res://tests/run_tests.gd", "--log-file", (Join-Path $evidenceDir "godot_tests.log")) },
	$formatCheck
)
$environment = [ordered]@{
	engine = "unavailable"
	engine_executable = $GodotPath
	os = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
	process_architecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
	powershell = $PSVersionTable.PSVersion.ToString()
	python = $python
	gdformat = if ($null -ne $gdformat) { "version captured by format_check" } else { "unavailable; gdtoolkit 4.5.0 required" }
	cwd = $projectRoot
	started = $started
}
# The step log is written after this run, so hashing it would make its final hash self-referential.
$trackedInputs = @(
	"project.godot", "实施计划与验收基线.md", "docs/baselines/g0.json", "docs/内容层契约.md",
	"docs/G2冻结未完成项.md", "data", "src/battle",
	"src/common/game_constants.gd", "src/common/action_preview.gd", "src/common/random_source.gd", "src/content",
	"README.md", "docs/战斗模块契约.md", "docs/接口文档.md", "docs/数据库与实体关系设计.md",
	"docs/G3战斗规则执行记录.md", "tools/g2_content_builder.py",
	"tests/run_tests.gd", "tests/suites", "tests/fixtures/content_loader",
	"tools/verify_g2.py", "tools/verify_g3.ps1"
)
$inputHashes = [ordered]@{}
$missingInputs = @()
$rootPrefix = $projectRoot.TrimEnd('\') + '\'
foreach ($item in $trackedInputs) {
	$path = Join-Path $projectRoot $item
	if (Test-Path -LiteralPath $path -PathType Leaf) {
		$inputHashes[$item.Replace("\", "/")] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
	} elseif (Test-Path -LiteralPath $path -PathType Container) {
		Get-ChildItem -LiteralPath $path -File -Recurse | Sort-Object FullName | ForEach-Object {
			$relative = $_.FullName.Substring($rootPrefix.Length).Replace("\", "/")
			$inputHashes[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
		}
	} else {
		$missingInputs += $item
	}
}

$passed = $false
$failure = $null
try {
	if ($missingInputs.Count -gt 0) {
		throw "Tracked input paths are missing: $($missingInputs -join ', ')"
	}
	Invoke-RecordedCommand -Name "engine_version" -Executable $GodotPath -Arguments @("--version") | Out-Null
	$actualVersion = (Get-Content -Raw -Encoding UTF8 (Join-Path $evidenceDir "engine_version.stdout.txt")).Trim()
	$environment.engine = $actualVersion
	if (-not ($actualVersion -eq $expectedVersion -or $actualVersion.StartsWith("$expectedVersion."))) {
		throw "Expected Godot $expectedVersion, found '$actualVersion'."
	}
	if ($null -ne $gdformat) {
		Invoke-RecordedCommand -Name "format_tool_version" -Executable $gdformat -Arguments @("--version") | Out-Null
		$environment.gdformat = (Get-Content -Raw -Encoding UTF8 (Join-Path $evidenceDir "format_tool_version.stdout.txt")).Trim()
	} else {
		$environment.gdformat = "unavailable"
	}
	[System.IO.File]::WriteAllText((Join-Path $evidenceDir "environment.json"), ($environment | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
	foreach ($command in $commands) {
		if ($command.name -eq "g2_static_audit") {
			$g2StageStatus = "failed"
		}
		Invoke-RecordedCommand -Name $command.name -Executable $command.executable -Arguments $command.arguments | Out-Null
		if ($command.name -eq "g2_static_audit" -and $holdbackCount -eq 0) {
			$g2StageStatus = "passed"
		}
	}
	$headlessOutput = (Get-Content -Raw -Encoding UTF8 (Join-Path $evidenceDir "headless_tests.stdout.txt"))
	if (-not ($headlessOutput -match "G1/G2/G3 headless tests passed")) {
		throw "G3 headless suite success marker was not found. See $evidenceDir"
	}
	if ($Step -eq "G3-05" -and $missingPriorSteps.Count -gt 0) {
		throw "Prior G3 step evidence is missing or failed: $($missingPriorSteps -join ', ')"
	}
	$passed = $true
} catch {
	$failure = $_.Exception.Message
}

$stageCompleted = $Step -eq "G3-05" -and $passed -and $missingPriorSteps.Count -eq 0
$stageStatus = if ($stageCompleted) { "completed" } else { "in_progress" }

[System.IO.File]::WriteAllText((Join-Path $evidenceDir "inputs.json"), ($inputHashes | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
$commandRecord = @([ordered]@{ name = "engine_version"; executable = $GodotPath; arguments = @("--version") })
if ($null -ne $gdformat) {
	$commandRecord += [ordered]@{ name = "format_tool_version"; executable = $gdformat; arguments = @("--version") }
}
$commandRecord += @($commands)
[System.IO.File]::WriteAllText((Join-Path $evidenceDir "command.json"), ($commandRecord | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $evidenceDir "report.json"), ([ordered]@{
	stage = "G3"
	step = $Step
	verification = $(if ($passed) { "passed" } else { "failed" })
	stage_status = $stageStatus
	g2_stage_status = $g2StageStatus
	g2_holdback_count = $holdbackCount
	prior_step_evidence = $priorStepEvidence
	missing_prior_steps = $missingPriorSteps
	missing_inputs = $missingInputs
	failure = $failure
	godot = $environment.engine
} | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
$reportLines = @(
	"# $Step verification", "", "- Run ID: ``$runId``",
	"- Verification: $(if ($passed) { "passed" } else { "failed" })",
	"- G3 stage status: $stageStatus", "- G2 status: $g2StageStatus ($holdbackCount production definitions held back)",
	"- Prior step evidence: ``$($priorStepEvidence | ConvertTo-Json -Compress)``",
	"- Godot: ``$($environment.engine)``", "- Failure: $(if ($failure) { $failure } else { "none" })",
	"- Started: ``$started``"
)
[System.IO.File]::WriteAllLines((Join-Path $evidenceDir "report.md"), $reportLines)
$resultCode = if ($passed) { 0 } else { 1 }
[System.IO.File]::WriteAllText((Join-Path $evidenceDir "exit_code.txt"), "$resultCode`n", [System.Text.UTF8Encoding]::new($false))
Write-Output "$Step verification: $(if ($passed) { "passed" } else { "failed" })"
Write-Output "G3 stage: $stageStatus; G2 status: $g2StageStatus; G2 holdback: $holdbackCount"
Write-Output "Evidence: $evidenceDir"
if ($failure) { Write-Error $failure }
exit $resultCode
