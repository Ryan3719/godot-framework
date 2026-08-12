param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,
    [string]$GodotBin = "godot"
)

$ErrorActionPreference = "Stop"
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$ProjectDir = Join-Path ([System.IO.Path]::GetTempPath()) ("godot-framework-windows-export-" + [guid]::NewGuid())
$ExportDir = Join-Path ([System.IO.Path]::GetTempPath()) ("godot-framework-windows-build-" + [guid]::NewGuid())
$FailurePattern = "SCRIPT ERROR|Parse Error|^ERROR:|ObjectDB instances leaked|instances were leaked|resources still in use"

function Invoke-Logged {
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [string]$LogPath
    )

    & $Executable @Arguments *> $LogPath
    if ($LASTEXITCODE -ne 0) {
        Get-Content $LogPath
        throw "Command failed with exit code $LASTEXITCODE`: $Executable"
    }
}

try {
    New-Item -ItemType Directory -Path $ProjectDir, $ExportDir | Out-Null
    python "$RepositoryRoot/scripts/verify_addon_package.py" $PackagePath
    if ($LASTEXITCODE -ne 0) {
        throw "Addon package verification failed."
    }
    Copy-Item "$RepositoryRoot/tests/package_install_project/*" $ProjectDir -Recurse
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $ProjectDir

    $EditorLog = Join-Path $ProjectDir "editor.log"
    $ExportLog = Join-Path $ProjectDir "export.log"
    $RunLog = Join-Path $ProjectDir "export-run.log"
    $Executable = Join-Path $ExportDir "godot-framework-test.exe"
    $ConsoleExecutable = Join-Path $ExportDir "godot-framework-test.console.exe"

    Invoke-Logged $GodotBin @("--headless", "--editor", "--quit", "--path", $ProjectDir) $EditorLog
    Invoke-Logged $GodotBin @("--headless", "--path", $ProjectDir, "--export-release", "Windows", $Executable) $ExportLog
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
        throw "Windows export did not create the executable."
    }
    if (-not (Test-Path -LiteralPath $ConsoleExecutable -PathType Leaf)) {
        throw "Windows release export did not create the console wrapper."
    }
    Push-Location $ExportDir
    try {
        Invoke-Logged $ConsoleExecutable @("--headless", "--verbose") $RunLog
    } finally {
        Pop-Location
    }

    $RunOutput = Get-Content $RunLog -Raw
    if (-not $RunOutput.Contains("[EXPORT TEST] PASS: packaged addon runs in release export")) {
        Get-Content $RunLog
        throw "Windows export runtime marker was not found."
    }
    foreach ($LogPath in @($EditorLog, $ExportLog, $RunLog)) {
        if (Select-String -Path $LogPath -Pattern $FailurePattern) {
            throw "Framework error or leak marker found in $LogPath."
        }
    }
    Write-Output "[EXPORT TEST] PASS: packaged addon runs in Windows release export"
} finally {
    Remove-Item -LiteralPath $ProjectDir, $ExportDir -Recurse -Force -ErrorAction SilentlyContinue
}
