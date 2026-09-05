param(
    [Parameter(Mandatory = $true)]
    [string]$CodeCoveragePath,
    [string]$BdsVersion = '23.0',
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'coverage'),
    [ValidateRange(0, 100)]
    [int]$MinimumLineCoverage = 85
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path $PSScriptRoot -Parent
$rsvars = "C:\Program Files (x86)\Embarcadero\Studio\$BdsVersion\bin\rsvars.bat"
$msbuild = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe"
$testProject = Join-Path $PSScriptRoot 'AtroposTests.dproj'
$testExecutable = Join-Path $PSScriptRoot 'AtroposTests.exe'
$mapFile = Join-Path $PSScriptRoot 'AtroposTests.map'

if (-not (Test-Path -LiteralPath $CodeCoveragePath)) { throw "Coverage executable not found: $CodeCoveragePath" }
if (-not (Test-Path -LiteralPath $rsvars)) { throw "RAD Studio environment not found: $rsvars" }

$buildCommand = "`"$rsvars`" && `"$msbuild`" `"$testProject`" /t:Build /p:Config=Debug /p:Platform=Win32 /nologo /v:minimal"
& cmd.exe /d /c $buildCommand
if ($LASTEXITCODE -ne 0) { throw "Test build failed with exit code $LASTEXITCODE" }

$units = @(
    'Atropos.Core.Domain', 'Atropos.Core.Config', 'Atropos.Core.Modifier',
    'Atropos.Application.AppService', 'Atropos.Application.ExecutionConfig',
    'Atropos.Application.ExecutionLifecycle',
    'Atropos.Application.CommandLine',
    'Atropos.Adapters.BuildService', 'Atropos.Adapters.DelphiEnvironment',
    'Atropos.Adapters.ExternalUnitResolver', 'Atropos.Adapters.FileSystem',
    'Atropos.Adapters.ProjectParser', 'Atropos.Adapters.ReportGenerator',
    'Atropos.Adapters.DelphiAST'
)
$sourcePaths = @(
    'src\Core\Domain', 'src\Core\Services', 'src\Application',
    'src\Adapters\BuildService', 'src\Adapters\DelphiEnvironment',
    'src\Adapters\ExternalUnitResolver', 'src\Adapters\FileSystem',
    'src\Adapters\ProjectParser', 'src\Adapters\ReportGenerator',
    'src\Adapters\DelphiAST'
) | ForEach-Object { Join-Path $repositoryRoot $_ }

$arguments = @('-e', $testExecutable, '-m', $mapFile, '-ife', '-u') + $units +
    @('-sd', $repositoryRoot, '-od', $OutputDirectory, '-sp') + $sourcePaths +
    @('-html', '-xml', '-xmllines', '-tec', '-twd')

& $CodeCoveragePath @arguments
if ($LASTEXITCODE -ne 0) { throw "Coverage run failed with exit code $LASTEXITCODE" }

$summary = Join-Path $OutputDirectory 'CodeCoverage_Summary.xml'
[xml]$report = Get-Content -Raw -LiteralPath $summary
$lineCoverage = $report.report.data.all.coverage | Where-Object { $_.type -eq 'line, %' }
Write-Host "Line coverage: $($lineCoverage.value)"
$coveragePercent = [int]([regex]::Match($lineCoverage.value, '^\d+').Value)
if ($coveragePercent -lt $MinimumLineCoverage) {
    throw "Line coverage $coveragePercent% is below the required $MinimumLineCoverage%."
}
