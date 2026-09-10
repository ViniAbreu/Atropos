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
$env:ATROPOS_TEST_BDS_PATH = Split-Path (Split-Path $rsvars -Parent) -Parent
$msbuild = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe"

if (-not (Test-Path -LiteralPath $rsvars)) { throw "RAD Studio environment not found: $rsvars" }

& (Join-Path $PSScriptRoot 'test-documentation.ps1')
& (Join-Path $PSScriptRoot 'test-release.ps1')
& (Join-Path $PSScriptRoot 'test-architecture-guard.ps1')
& (Join-Path $PSScriptRoot 'test-architecture.ps1')

function Invoke-DelphiBuild([string]$Project, [string]$Configuration, [string]$Platform) {
    $projectPath = Join-Path $repositoryRoot $Project
    $libraryPath = "C:\Program Files (x86)\Embarcadero\Studio\$BdsVersion\lib\$Platform\$Configuration"
    $command = "`"$rsvars`" && `"$msbuild`" `"$projectPath`" /t:Build /p:Config=$Configuration /p:Platform=$Platform /p:DelphiLibraryPath=`"$libraryPath`" /nologo /v:minimal"
    & cmd.exe /d /c $command
    if ($LASTEXITCODE -ne 0) { throw "$Project build failed with exit code $LASTEXITCODE" }
}

foreach ($platform in @('Win32', 'Win64')) {
    Invoke-DelphiBuild 'tests\AtroposTests.dproj' 'Debug' $platform
    $testExecutable = Join-Path $PSScriptRoot "$platform\Debug\AtroposTests.exe"
    & $testExecutable --consolemode:quiet
    if ($LASTEXITCODE -ne 0) { throw "$platform tests failed with exit code $LASTEXITCODE" }

    Invoke-DelphiBuild 'AtroposCLI.dproj' 'Release' $platform
    Invoke-DelphiBuild 'AtroposVCL.dproj' 'Release' $platform
    & (Join-Path $PSScriptRoot 'run-smoke-test.ps1') `
        -CliPath (Join-Path $repositoryRoot "$platform\Release\AtroposCLI.exe") -Platform $platform
    & (Join-Path $PSScriptRoot 'run-representative-smoke-tests.ps1') `
        -CliPath (Join-Path $repositoryRoot "$platform\Release\AtroposCLI.exe") -Platform $platform
    & (Join-Path $PSScriptRoot 'run-lifecycle-smoke-test.ps1') `
        -CliPath (Join-Path $repositoryRoot "$platform\Release\AtroposCLI.exe") -Platform $platform
}

& (Join-Path $PSScriptRoot 'run-coverage.ps1') -CodeCoveragePath $CodeCoveragePath `
    -BdsVersion $BdsVersion -MinimumLineCoverage $MinimumLineCoverage
