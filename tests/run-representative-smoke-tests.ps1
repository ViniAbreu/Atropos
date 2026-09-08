param(
    [Parameter(Mandatory = $true)]
    [string]$CliPath,
    [Parameter(Mandatory = $true)]
    [ValidateSet('Win32', 'Win64')]
    [string]$Platform
)

$ErrorActionPreference = 'Stop'
$fixturesRoot = Join-Path $PSScriptRoot 'Fixtures'
$resolvedCliPath = (Resolve-Path -LiteralPath $CliPath).Path

function Get-FixtureHashes([string]$FixturePath) {
    $hashes = @{}
    Get-ChildItem -LiteralPath $FixturePath -File -Recurse | ForEach-Object {
        $relativePath = [System.IO.Path]::GetRelativePath($FixturePath, $_.FullName)
        $hashes[$relativePath] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
    $hashes
}

function Assert-FixtureUnchanged([string]$FixturePath, [hashtable]$ExpectedHashes) {
    $currentHashes = Get-FixtureHashes $FixturePath
    if ($currentHashes.Count -ne $ExpectedHashes.Count) {
        throw "Repository fixture file count changed: $FixturePath"
    }
    foreach ($relativePath in $ExpectedHashes.Keys) {
        if ($currentHashes[$relativePath] -ne $ExpectedHashes[$relativePath]) {
            throw "Repository fixture changed: $relativePath"
        }
    }
}

function Invoke-Fixture([string]$FixtureName, [string]$ProjectName, [string]$SourceName, [string]$RemovedUnitName, [bool]$SimulateRecovery, [bool]$ExpectRollback) {
    $fixturePath = Join-Path $fixturesRoot $FixtureName
    $fixtureHashes = Get-FixtureHashes $fixturePath
    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('AtroposFixture-' + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
        Copy-Item -LiteralPath $fixturePath -Destination $temporaryRoot -Recurse
        $workingFixture = Join-Path $temporaryRoot $FixtureName
        $projectPath = Join-Path $workingFixture $ProjectName
        $sourcePath = Join-Path $workingFixture $SourceName
        $originalSourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        $reportPath = Join-Path $workingFixture 'reports\AtroposReport.txt'
        $standardOutputPath = Join-Path $temporaryRoot 'stdout.txt'
        $standardErrorPath = Join-Path $temporaryRoot 'stderr.txt'
        if ($SimulateRecovery) {
            $transactionId = [Guid]::NewGuid().ToString('D')
            $backupPath = $sourcePath + '.atropos-' + $transactionId + '.bak'
            $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
            Copy-Item -LiteralPath $sourcePath -Destination $backupPath
            @{
                version = 1
                transactionId = $transactionId
                state = 'active'
                createdUtc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                entries = @(@{
                    original = $sourcePath
                    backup = $backupPath
                    sha256 = $sourceHash
                })
            } | ConvertTo-Json -Depth 4 -Compress | Set-Content -LiteralPath `
                (Join-Path $workingFixture '.atropos-transaction.json') -Encoding utf8NoBOM
            Set-Content -LiteralPath $sourcePath -Value 'invalid source awaiting recovery' -Encoding utf8NoBOM
        }
        $process = Start-Process -FilePath $resolvedCliPath -ArgumentList @(
            '-dproj', ('"' + $projectPath + '"'), '--remove', '-txt', '--output', 'reports',
            '--target', ("Debug|$Platform")
        ) -RedirectStandardOutput $standardOutputPath -RedirectStandardError $standardErrorPath -PassThru -WindowStyle Hidden
        if (-not $process.WaitForExit(180000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            throw "$Platform $FixtureName smoke test timed out after 180 seconds."
        }
        $process.WaitForExit()
        if ($ExpectRollback) {
            if ($process.ExitCode -eq 0) {
                throw "$Platform $FixtureName should fail its verification build."
            }
            $restoredHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
            if ($restoredHash -ne $originalSourceHash) {
                throw "$Platform $FixtureName did not restore its modified source."
            }
            if (Get-ChildItem -LiteralPath $workingFixture -Filter '*.atropos-*.bak' -Recurse) {
                throw "$Platform $FixtureName left transaction backups after rollback."
            }
            Assert-FixtureUnchanged $fixturePath $fixtureHashes
            Write-Host "$Platform $FixtureName rollback smoke test passed."
            return
        }
        if ($process.ExitCode -ne 0) {
            $processOutput = (Get-Content -Raw -LiteralPath $standardOutputPath) + (Get-Content -Raw -LiteralPath $standardErrorPath)
            throw "$Platform $FixtureName smoke test failed with exit code $($process.ExitCode). $processOutput"
        }
        $sourceContent = Get-Content -Raw -LiteralPath $sourcePath
        if ($sourceContent -match [regex]::Escape($RemovedUnitName)) {
            throw "$Platform $FixtureName did not remove $RemovedUnitName."
        }
        if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
            throw "$Platform $FixtureName did not generate its report."
        }
        $reportContent = Get-Content -Raw -LiteralPath $reportPath
        if ($reportContent -notmatch [regex]::Escape($RemovedUnitName)) {
            throw "$Platform $FixtureName report does not record $RemovedUnitName."
        }
        if (Get-ChildItem -LiteralPath $workingFixture -Filter '*.atropos-*.bak' -Recurse) {
            throw "$Platform $FixtureName left transaction backups after success."
        }
        Assert-FixtureUnchanged $fixturePath $fixtureHashes
        Write-Host "$Platform $FixtureName representative smoke test passed."
    }
    finally {
        $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
        $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if ($resolvedTemporaryRoot.StartsWith($resolvedSystemTemp, [StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path $resolvedTemporaryRoot -Leaf).StartsWith('AtroposFixture-', [StringComparison]::Ordinal)) {
            Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Invoke-Fixture 'RepresentativeConsole' 'RepresentativeConsole.dproj' 'Fixture.Main.pas' 'Fixture.Unused' $true $false
Invoke-Fixture 'RepresentativeVCL' 'RepresentativeVCL.dproj' 'Fixture.VclMain.pas' 'Fixture.VclUnused' $false $false
Invoke-Fixture 'RollbackConsole' 'RollbackConsole.dproj' 'Rollback.Main.pas' 'Rollback.Unused' $false $true
