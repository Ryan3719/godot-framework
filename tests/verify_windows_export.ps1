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
        [string[]]$CommandArgs,
        [string]$LogPath
    )

    $StdoutPath = "$LogPath.stdout"
    $StderrPath = "$LogPath.stderr"
    $Process = Start-Process -FilePath $Executable -ArgumentList $CommandArgs -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
    $Stdout = if (Test-Path -LiteralPath $StdoutPath) { Get-Content $StdoutPath -Raw } else { "" }
    $Stderr = if (Test-Path -LiteralPath $StderrPath) { Get-Content $StderrPath -Raw } else { "" }
    Set-Content -LiteralPath $LogPath -Value ($Stdout + $Stderr) -NoNewline
    Remove-Item -LiteralPath $StdoutPath, $StderrPath -Force -ErrorAction SilentlyContinue
    if ($Process.ExitCode -ne 0) {
        Get-Content $LogPath
        throw "Command failed with exit code $($Process.ExitCode)`: $Executable"
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

    $ExportTarget = $Executable.Replace("\", "/")
    Invoke-Logged -Executable $GodotBin -CommandArgs @("--headless", "--editor", "--quit", "--path", $ProjectDir) -LogPath $EditorLog
    Invoke-Logged -Executable $GodotBin -CommandArgs @("--headless", "--path", $ProjectDir, "--export-release", "Windows", $ExportTarget) -LogPath $ExportLog
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
        Get-Content $ExportLog
        Get-ChildItem -LiteralPath $ProjectDir, $ExportDir -Recurse | Select-Object -ExpandProperty FullName
        throw "Windows export did not create the executable."
    }
    if (-not (Test-Path -LiteralPath $ConsoleExecutable -PathType Leaf)) {
        throw "Windows release export did not create the console wrapper."
    }
    Push-Location $ExportDir
    try {
        Invoke-Logged -Executable $ConsoleExecutable -CommandArgs @("--headless", "--verbose") -LogPath $RunLog
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
