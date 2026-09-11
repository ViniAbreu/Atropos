param(
    [Parameter(Mandatory = $true)]
    [string]$CodeCoveragePath,
    [string]$BdsVersion = '23.0',
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'coverage'),
    [ValidateRange(0, 100)]
    [int]$MinimumLineCoverage = 85,
    [ValidateRange(0, 100)]
    [int]$MinimumUnitLineCoverage = 60
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path $PSScriptRoot -Parent
$rsvars = "C:\Program Files (x86)\Embarcadero\Studio\$BdsVersion\bin\rsvars.bat"
$env:ATROPOS_TEST_BDS_PATH = Split-Path (Split-Path $rsvars -Parent) -Parent
$msbuild = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe"
$testProject = Join-Path $PSScriptRoot 'AtroposTests.dproj'
$testExecutable = Join-Path $PSScriptRoot 'Win32\Debug\AtroposTests.exe'
$mapFile = Join-Path $PSScriptRoot 'Win32\Debug\AtroposTests.map'

if (-not (Test-Path -LiteralPath $CodeCoveragePath)) { throw "Coverage executable not found: $CodeCoveragePath" }
if (-not (Test-Path -LiteralPath $rsvars)) { throw "RAD Studio environment not found: $rsvars" }

$libraryPath = "C:\Program Files (x86)\Embarcadero\Studio\$BdsVersion\lib\Win32\Debug"
$buildCommand = "`"$rsvars`" && `"$msbuild`" `"$testProject`" /t:Build /p:Config=Debug /p:Platform=Win32 /p:DelphiLibraryPath=`"$libraryPath`" /nologo /v:minimal"
& cmd.exe /d /c $buildCommand
if ($LASTEXITCODE -ne 0) { throw "Test build failed with exit code $LASTEXITCODE" }

$units = @(
    'Atropos.Core.Domain', 'Atropos.Core.Analysis', 'Atropos.Core.AnalysisIntersection', 'Atropos.Core.Effects', 'Atropos.Core.Config', 'Atropos.Core.Modifier',
    'Atropos.Application.AppService', 'Atropos.Application.ExecutionConfig',
    'Atropos.Application.ExecutionLifecycle',
    'Atropos.Application.ExecutionPresentation',
    'Atropos.Application.CommandLine',
    'Atropos.Application.Factory', 'Atropos.App.CLI',
    'Atropos.Adapters.Logger',
    'Atropos.Adapters.BuildService', 'Atropos.Adapters.BuildCapability',
    'Atropos.Adapters.ExecutionThread',
    'Atropos.Adapters.DelphiEnvironment',
    'Atropos.Adapters.ExternalUnitResolver', 'Atropos.Adapters.UnitDependencies', 'Atropos.Adapters.FileSystem',
    'Atropos.Adapters.FileTransaction',
    'Atropos.Adapters.ProjectParser', 'Atropos.Adapters.ProjectContext', 'Atropos.Adapters.CompilerSymbols', 'Atropos.Adapters.ProjectSourceMappings', 'Atropos.Adapters.TargetAnalysisFactory', 'Atropos.Adapters.TargetResolver', 'Atropos.Adapters.ContextSyntaxBuilder', 'Atropos.Adapters.ConditionalImports', 'Atropos.Adapters.SyntaxFacts', 'Atropos.Adapters.SyntaxBuilder', 'Atropos.Application.TargetAnalysis', 'Atropos.Application.Logger', 'Atropos.Adapters.ProjectEvaluationScript', 'Atropos.Adapters.ReportGenerator',
    'Atropos.Adapters.DelphiAST', 'Atropos.Adapters.DelphiSource',
    'Atropos.Adapters.SourceIncludes', 'Atropos.Adapters.SourceSnapshot', 'Atropos.Application.AnalysisPlan'
)
$sourcePaths = @(
    'src\Core\Domain', 'src\Core\Services', 'src\Application', 'src\CLI',
    'src\Adapters\Logger',
    'src\Adapters\BuildService', 'src\Adapters\Execution',
    'src\Adapters\DelphiEnvironment',
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

$unitFailures = [System.Collections.Generic.List[string]]::new()
foreach ($unit in $report.report.data.all.package) {
    $unitLineCoverage = $unit.coverage | Where-Object { $_.type -eq 'line, %' }
    $unitCoveragePercent = [int]([regex]::Match($unitLineCoverage.value, '^\d+').Value)
    Write-Host "$($unit.name): $($unitLineCoverage.value)"
    if ($unitCoveragePercent -lt $MinimumUnitLineCoverage) {
        $unitFailures.Add("$($unit.name): $($unitLineCoverage.value)")
    }
}

if ($unitFailures.Count -gt 0) {
    throw "Unit coverage below $MinimumUnitLineCoverage%: $($unitFailures -join '; ')"
}
