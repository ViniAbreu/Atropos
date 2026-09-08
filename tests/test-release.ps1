$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\Atropos.ReleaseTools.ps1')
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ("AtroposReleaseTools-" + [guid]::NewGuid().ToString('N'))
$staging = Join-Path $fixtureRoot 'staging'
New-Item -ItemType Directory -Path (Join-Path $staging 'docs') -Force | Out-Null

try {
    Set-Content -LiteralPath (Join-Path $staging 'AtroposCLI.exe') `
        -Value 'binary fixture' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $staging 'docs\README.md') `
        -Value 'documentation fixture' -Encoding UTF8
    $manifestPath = New-ReleaseManifest $staging '2.3.4' 'Win64' ('a' * 40) `
        ('b' * 40) '23.0' 1234567890
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    $manifestBytes = [System.IO.File]::ReadAllBytes($manifestPath)
    if (($manifestBytes.Length -ge 3) -and ($manifestBytes[0] -eq 0xEF) -and
        ($manifestBytes[1] -eq 0xBB) -and ($manifestBytes[2] -eq 0xBF)) {
        throw 'Manifest must use UTF-8 without a BOM.'
    }
    if ($manifest.schemaVersion -ne 1) { throw 'Unexpected manifest schema.' }
    if ($manifest.version -ne '2.3.4') { throw 'Manifest version was not preserved.' }
    if ($manifest.platform -ne 'Win64') { throw 'Manifest platform was not preserved.' }
    if ($manifest.sourceDateEpoch -ne 1234567890) {
        throw 'Manifest source timestamp was not preserved.'
    }
    if ($manifest.files.Count -ne 2) { throw 'Manifest file inventory is incomplete.' }
    foreach ($file in $manifest.files) {
        $path = Join-Path $staging $file.path.Replace('/', '\')
        $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $file.sha256) { throw "Manifest hash mismatch for $($file.path)." }
    }

    $firstZip = Join-Path $fixtureRoot 'first.zip'
    $secondZip = Join-Path $fixtureRoot 'second.zip'
    New-DeterministicZip $staging $firstZip | Out-Null
    Get-ChildItem -LiteralPath $staging -File -Recurse | ForEach-Object {
        $_.LastWriteTimeUtc = [datetime]::UtcNow
    }
    New-DeterministicZip $staging $secondZip | Out-Null
    $firstHash = (Get-FileHash -LiteralPath $firstZip -Algorithm SHA256).Hash
    $secondHash = (Get-FileHash -LiteralPath $secondZip -Algorithm SHA256).Hash
    if ($firstHash -ne $secondHash) { throw 'ZIP output changes with file timestamps.' }

    $checksumPath = Join-Path $fixtureRoot 'SHA256SUMS.txt'
    New-ChecksumFile @($secondZip, $firstZip) $checksumPath
    $checksumLines = @(Get-Content -LiteralPath $checksumPath)
    if ($checksumLines.Count -ne 2) { throw 'Checksum inventory is incomplete.' }
    if (-not $checksumLines[0].EndsWith('  first.zip')) {
        throw 'Checksum inventory is not sorted.'
    }

    $invalidVersionRejected = $false
    try { Assert-ReleaseVersion 'v2.3' } catch { $invalidVersionRejected = $true }
    if (-not $invalidVersionRejected) { throw 'Invalid version was accepted.' }
    if ((ConvertTo-FileVersion '2.3.4-beta.1') -ne '2.3.4.0') {
        throw 'File version conversion failed.'
    }
    $hostVersion = Get-BinaryFileVersion (Get-Process -Id $PID).Path
    if (-not $hostVersion) { throw 'Binary version could not be read.' }
    $missingBinaryRejected = $false
    try {
        Get-BinaryFileVersion (Join-Path $fixtureRoot 'missing.exe') | Out-Null
    } catch {
        $missingBinaryRejected = $true
    }
    if (-not $missingBinaryRejected) { throw 'Missing release binary was accepted.' }

    $firstPE = Join-Path $fixtureRoot 'first.exe'
    $secondPE = Join-Path $fixtureRoot 'second.exe'
    Copy-Item -LiteralPath (Get-Process -Id $PID).Path -Destination $firstPE
    Copy-Item -LiteralPath $firstPE -Destination $secondPE
    $secondBytes = [System.IO.File]::ReadAllBytes($secondPE)
    $secondPEOffset = [BitConverter]::ToInt32($secondBytes, 0x3C)
    [BitConverter]::GetBytes([uint32]42).CopyTo($secondBytes, $secondPEOffset + 8)
    [System.IO.File]::WriteAllBytes($secondPE, $secondBytes)
    Normalize-PEMetadata $firstPE 1234567890
    Normalize-PEMetadata $secondPE 1234567890
    if ((Get-FileHash $firstPE).Hash -ne (Get-FileHash $secondPE).Hash) {
        throw 'PE timestamp normalization is not deterministic.'
    }
    $invalidPERejected = $false
    try { Normalize-PEMetadata (Join-Path $staging 'AtroposCLI.exe') 1 } catch {
        $invalidPERejected = $true
    }
    if (-not $invalidPERejected) { throw 'Invalid PE input was accepted.' }
} finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}

$global:LASTEXITCODE = 0
Write-Host 'Release tooling regression tests passed.'
