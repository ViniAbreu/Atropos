Set-StrictMode -Version Latest

function Get-ProbeSourceHashes([string]$ProbeRoot) {
    $repository = [IO.Path]::GetFullPath((Join-Path $ProbeRoot '../..'))
    $files = @(Get-Item (Join-Path $ProbeRoot 'Probe.dpr'), (Join-Path $ProbeRoot 'Probe.dproj'))
    foreach ($directory in @('src', '../../src', '../../third_party/DelphiAST/Source')) {
        $files += Get-ChildItem (Join-Path $ProbeRoot $directory) -Recurse -File |
            Where-Object Extension -in @('.pas', '.inc')
    }
    foreach ($file in ($files | Sort-Object FullName)) {
        [pscustomobject]@{
            path=$file.FullName.Substring($repository.Length + 1).Replace('\', '/')
            sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
    }
}

function Assert-ProbeSourceHashes($Expected, $Actual) {
    $expectedEntries = @($Expected | ForEach-Object { $_.path + ':' + $_.sha256 } | Sort-Object)
    $actualEntries = @($Actual | ForEach-Object { $_.path + ':' + $_.sha256 } | Sort-Object)
    if (($expectedEntries -join "`n") -cne ($actualEntries -join "`n")) {
        throw 'Probe source inputs changed. Run Build-Probe.ps1 before collecting results.'
    }
}

function Get-ProbeGitRevision([string]$Directory) {
    $revision = & git -C $Directory rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw "Cannot read Git revision: $Directory" }
    return [string]$revision
}
