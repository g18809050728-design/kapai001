param(
	[string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$runId = "g4-" + (Get-Date -Format "yyyyMMdd-HHmmss-fff") + "-" + [guid]::NewGuid().ToString("N").Substring(0, 6)
$evidenceDir = Join-Path $projectRoot (Join-Path "artifacts/verification" $runId)
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
$started = (Get-Date).ToString("o")
$expectedVersion = "4.7.2.stable"
$env:PYTHONUTF8 = "1"
$godotProblem = $null
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
	$installedConsole = 'F:\GoDot\Godot_v4.7.2-stable_win64_console.exe'
	$godotCommand = Get-Command godot -ErrorAction SilentlyContinue
	if (Test-Path -LiteralPath $installedConsole -PathType Leaf) {
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
    if ($Name -eq "headless_tests" -and $log -notmatch "G4 headless tests passed") {
        throw "G4 success marker missing. See $evidenceDir"
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
    $testLog = Get-Content -Encoding UTF8 (Join-Path $evidenceDir "headless_tests.stdout.txt")
    foreach ($entry in @(@{prefix="G4_RUN_COMMANDS="; file="run_commands.json"}, @{prefix="G4_ROUTE_EVIDENCE="; file="routes.json"})) {
        $line = @($testLog | Where-Object { $_.StartsWith($entry.prefix) })
        if ($line.Count -ne 1) { throw "Missing G4 route evidence: $($entry.prefix)" }
        $json = $line[0].Substring($entry.prefix.Length)
        $null = ConvertFrom-Json -InputObject $json
        [System.IO.File]::WriteAllText((Join-Path $evidenceDir $entry.file), $json, [System.Text.UTF8Encoding]::new($false))
    }
    if ((ConvertFrom-Json -InputObject (Get-Content -Raw -Encoding UTF8 (Join-Path $evidenceDir "routes.json"))).Count -ne 4) { throw "Expected four G4 routes" }
    $allPassed = $true
} catch {
	$failure = $_.Exception.Message
}

$trackedInputs = @(
    "project.godot", "src", "tests", "data", "docs/baselines/g0.json",
    "docs/局流程契约.md", "docs/接口文档.md", "tools/verify_g2.py", "tools/verify_g4.ps1"
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
$stageStatus = if ($allPassed -and $holdbackCount -eq 0) { "passed" } else { "in_progress" }
[System.IO.File]::WriteAllText((Join-Path $evidenceDir "report.json"), ([ordered]@{ stage = "G4"; verification = $(if ($allPassed) { "passed" } else { "failed" }); stage_status = $stageStatus; holdback_count = $holdbackCount; failure = $failure; godot = $environment.engine } | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
$reportLines = @("# G4 verification", "", "- Run ID: ``$runId``", "- Verification: $(if ($allPassed) { "passed" } else { "failed" })", "- Stage status: $stageStatus", "- Production holdback definitions: $holdbackCount", "- Godot: ``$($environment.engine)``", "- Failure: $(if ($failure) { $failure } else { "none" })", "- Started: ``$started``")
[System.IO.File]::WriteAllLines((Join-Path $evidenceDir "report.md"), $reportLines, [System.Text.UTF8Encoding]::new($false))
$resultCode = if ($allPassed) { 0 } else { 1 }
[System.IO.File]::WriteAllText((Join-Path $evidenceDir "exit_code.txt"), "$resultCode`n", [System.Text.UTF8Encoding]::new($false))
Write-Output "G4 verification: $(if ($allPassed) { "passed" } else { "failed" })"
Write-Output "G4 stage: $stageStatus ($holdbackCount production definitions remain in holdback)"
Write-Output "Evidence: $evidenceDir"
if ($failure) { Write-Error $failure }
exit $resultCode
