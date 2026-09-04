param(
    [Parameter(Mandatory = $true)]
    [string]$CliPath,
    [Parameter(Mandatory = $true)]
    [ValidateSet('Win32', 'Win64')]
    [string]$Platform
)

$ErrorActionPreference = 'Stop'
$expectedMachine = @{ Win32 = 0x014c; Win64 = 0x8664 }

function Get-PeMachine([string]$ExecutablePath) {
    $bytes = [System.IO.File]::ReadAllBytes($ExecutablePath)
    if ($bytes.Length -lt 64) { throw "Invalid PE executable: $ExecutablePath" }
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
    if ($peOffset -lt 0 -or $peOffset + 6 -gt $bytes.Length) { throw "Invalid PE header: $ExecutablePath" }
    if ([BitConverter]::ToUInt32($bytes, $peOffset) -ne 0x00004550) { throw "PE signature not found: $ExecutablePath" }
    [BitConverter]::ToUInt16($bytes, $peOffset + 4)
}

if (-not (Test-Path -LiteralPath $CliPath -PathType Leaf)) { throw "CLI executable not found: $CliPath" }
$resolvedCliPath = (Resolve-Path -LiteralPath $CliPath).Path
$machine = Get-PeMachine $resolvedCliPath
if ($machine -ne $expectedMachine[$Platform]) {
    throw ('Expected {0} executable, PE machine is 0x{1:X4}.' -f $Platform, $machine)
}

$fixturePath = Join-Path $PSScriptRoot 'DummyProject'
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('AtroposSmoke-' + [Guid]::NewGuid().ToString('N'))
$originalUnitAHash = (Get-FileHash -LiteralPath (Join-Path $fixturePath 'UnitA.pas') -Algorithm SHA256).Hash

try {
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    Copy-Item -LiteralPath $fixturePath -Destination $temporaryRoot -Recurse
    $projectPath = Join-Path $temporaryRoot 'DummyProject\DummyProject.dproj'
    $unitAPath = Join-Path $temporaryRoot 'DummyProject\UnitA.pas'
    $reportPath = Join-Path $temporaryRoot 'DummyProject\reports\AtroposReport.txt'

    $standardOutputPath = Join-Path $temporaryRoot 'stdout.txt'
    $standardErrorPath = Join-Path $temporaryRoot 'stderr.txt'
    $process = Start-Process -FilePath $resolvedCliPath -ArgumentList @(
        '-dproj', ('"' + $projectPath + '"'), '--remove', '-txt', '--output', 'reports'
    ) -RedirectStandardOutput $standardOutputPath -RedirectStandardError $standardErrorPath -PassThru -WindowStyle Hidden
    if (-not $process.WaitForExit(180000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "$Platform smoke test timed out after 180 seconds."
    }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        $processOutput = (Get-Content -Raw -LiteralPath $standardOutputPath) + (Get-Content -Raw -LiteralPath $standardErrorPath)
        throw "$Platform smoke test failed with exit code $($process.ExitCode). $processOutput"
    }

    $unitAContent = Get-Content -Raw -LiteralPath $unitAPath
    if ($unitAContent -match '\bUnitB\b') { throw "$Platform smoke test did not remove the unused UnitB reference." }
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw "$Platform smoke test did not generate the TXT report." }
    $reportContent = Get-Content -Raw -LiteralPath $reportPath
    if ($reportContent -notmatch 'UnitB') { throw "$Platform smoke report does not record the removed UnitB reference." }
    if ((Get-FileHash -LiteralPath (Join-Path $fixturePath 'UnitA.pas') -Algorithm SHA256).Hash -ne $originalUnitAHash) {
        throw 'Smoke test changed the repository fixture.'
    }

    Write-Host "$Platform simulated real-use smoke test passed."
}
finally {
    $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
    $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolvedTemporaryRoot.StartsWith($resolvedSystemTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolvedTemporaryRoot -Leaf).StartsWith('AtroposSmoke-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
