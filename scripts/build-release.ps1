param(
    [Parameter(Mandatory = $true)] [string]$Version,
    [string]$BdsVersion = '23.0',
    [string]$OutputDirectory,
    [switch]$AllowDirty
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Atropos.ReleaseTools.ps1')
Assert-ReleaseVersion $Version
$repositoryRoot = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repositoryRoot 'artifacts\release'
}
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$status = git -C $repositoryRoot status --porcelain --untracked-files=all
if ((-not $AllowDirty) -and $status) {
    throw 'Release builds require a clean worktree.'
}

$sourceCommit = (git -C $repositoryRoot rev-parse HEAD).Trim()
$sourceDateEpoch = [long](git -C $repositoryRoot show -s --format=%ct HEAD)
$submoduleTree = (git -C $repositoryRoot ls-tree HEAD third_party/DelphiAST)
$expectedDelphiASTCommit = ($submoduleTree -split '\s+')[2]
$actualDelphiASTCommit = (git -C (Join-Path $repositoryRoot 'third_party\DelphiAST') rev-parse HEAD).Trim()
if ($expectedDelphiASTCommit -ne $actualDelphiASTCommit) {
    throw "DelphiAST mismatch: expected $expectedDelphiASTCommit, found $actualDelphiASTCommit."
}

$rsvars = "C:\Program Files (x86)\Embarcadero\Studio\$BdsVersion\bin\rsvars.bat"
$msbuild = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe"
if (-not (Test-Path -LiteralPath $rsvars -PathType Leaf)) {
    throw "RAD Studio environment not found: $rsvars"
}
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$fileVersion = ConvertTo-FileVersion $Version
$packages = [System.Collections.Generic.List[string]]::new()

foreach ($platform in @('Win32', 'Win64')) {
    $libraryPath = "C:\Program Files (x86)\Embarcadero\Studio\$BdsVersion\lib\$platform\Release"
    foreach ($project in @('AtroposCLI.dproj', 'AtroposVCL.dproj')) {
        $projectPath = Join-Path $repositoryRoot $project
        $command = "`"$rsvars`" && `"$msbuild`" `"$projectPath`" /t:Rebuild /p:Config=Release /p:Platform=$platform /p:ReleaseVersion=$fileVersion /p:DelphiLibraryPath=`"$libraryPath`" /nologo /v:minimal"
        & cmd.exe /d /c $command
        if ($LASTEXITCODE -ne 0) {
            throw "$project $platform build failed with exit code $LASTEXITCODE."
        }
    }

    $stagingDirectory = Join-Path $outputRoot ".staging-$platform"
    if (Test-Path -LiteralPath $stagingDirectory) {
        Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Path $stagingDirectory -Force | Out-Null
    try {
        foreach ($executable in @('AtroposCLI.exe', 'AtroposVCL.exe')) {
            $binaryPath = Join-Path $repositoryRoot "$platform\Release\$executable"
            Normalize-PEMetadata $binaryPath $sourceDateEpoch
            $binaryVersion = Get-BinaryFileVersion $binaryPath
            if ($binaryVersion -ne $fileVersion) {
                throw "$executable has version $binaryVersion; expected $fileVersion."
            }
            Copy-Item -LiteralPath $binaryPath -Destination $stagingDirectory
        }
        Copy-Item -LiteralPath (Join-Path $repositoryRoot 'README.md') `
            -Destination $stagingDirectory
        Copy-Item -LiteralPath (Join-Path $repositoryRoot 'LICENSE') `
            -Destination $stagingDirectory
        Copy-Item -LiteralPath (Join-Path $repositoryRoot 'docs') `
            -Destination $stagingDirectory -Recurse
        New-ReleaseManifest $stagingDirectory $Version $platform $sourceCommit `
            $actualDelphiASTCommit $BdsVersion $sourceDateEpoch | Out-Null
        $packagePath = Join-Path $outputRoot "Atropos-$Version-$platform.zip"
        New-DeterministicZip $stagingDirectory $packagePath | Out-Null
        $packages.Add($packagePath)
    } finally {
        if (Test-Path -LiteralPath $stagingDirectory) {
            Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
        }
    }
}

$checksumPath = Join-Path $outputRoot 'SHA256SUMS.txt'
New-ChecksumFile $packages.ToArray() $checksumPath
Write-Host "Release artifacts created in $outputRoot"
