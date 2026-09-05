param(
    [string]$BdsVersion = '23.0',
    [Parameter(Mandatory = $true)]
    [string]$CodeCoveragePath,
    [ValidateRange(0, 100)]
    [int]$MinimumLineCoverage = 85
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path $PSScriptRoot -Parent
$rsvars = "C:\Program Files (x86)\Embarcadero\Studio\$BdsVersion\bin\rsvars.bat"
$msbuild = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe"

if (-not (Test-Path -LiteralPath $rsvars)) { throw "RAD Studio environment not found: $rsvars" }

function Invoke-DelphiBuild([string]$Project, [string]$Configuration) {
    $projectPath = Join-Path $repositoryRoot $Project
    $command = "`"$rsvars`" && `"$msbuild`" `"$projectPath`" /t:Build /p:Config=$Configuration /p:Platform=Win32 /nologo /v:minimal"
    & cmd.exe /d /c $command
    if ($LASTEXITCODE -ne 0) { throw "$Project build failed with exit code $LASTEXITCODE" }
}

Invoke-DelphiBuild 'tests\AtroposTests.dproj' 'Debug'
& (Join-Path $PSScriptRoot 'AtroposTests.exe') --consolemode:quiet
if ($LASTEXITCODE -ne 0) { throw "Tests failed with exit code $LASTEXITCODE" }

Invoke-DelphiBuild 'AtroposCLI.dproj' 'Release'
Invoke-DelphiBuild 'AtroposVCL.dproj' 'Release'

& (Join-Path $PSScriptRoot 'run-coverage.ps1') -CodeCoveragePath $CodeCoveragePath `
    -BdsVersion $BdsVersion -MinimumLineCoverage $MinimumLineCoverage
