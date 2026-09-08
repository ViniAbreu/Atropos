Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Assert-ReleaseVersion([string]$Version) {
    if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
        throw "Invalid release version '$Version'. Use semantic versioning without a v prefix."
    }
}

function ConvertTo-FileVersion([string]$Version) {
    Assert-ReleaseVersion $Version
    $numericVersion = $Version.Split('-')[0]
    return "$numericVersion.0"
}

function Get-RelativeReleasePath([string]$Root, [string]$Path) {
    $rootPath = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    return $fullPath.Substring($rootPath.Length + 1).Replace('\', '/')
}

function New-ReleaseManifest([string]$StagingDirectory, [string]$Version,
    [string]$Platform, [string]$SourceCommit, [string]$DelphiASTCommit,
    [string]$BdsVersion, [long]$SourceDateEpoch) {
    Assert-ReleaseVersion $Version
    $files = @(Get-ChildItem -LiteralPath $StagingDirectory -File -Recurse |
        Sort-Object FullName | ForEach-Object {
        [ordered]@{
            path = Get-RelativeReleasePath $StagingDirectory $_.FullName
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            size = $_.Length
        }
    })
    $manifest = [ordered]@{
        schemaVersion = 1
        version = $Version
        platform = $Platform
        sourceCommit = $SourceCommit
        delphiASTCommit = $DelphiASTCommit
        bdsVersion = $BdsVersion
        sourceDateEpoch = $SourceDateEpoch
        files = $files
    }
    $manifestPath = Join-Path $StagingDirectory 'release-manifest.json'
    $manifestJson = $manifest | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($manifestPath, $manifestJson,
        [System.Text.UTF8Encoding]::new($false))
    return $manifestPath
}

function New-DeterministicZip([string]$SourceDirectory,
    [string]$DestinationPath) {
    $destination = [System.IO.Path]::GetFullPath($DestinationPath)
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Force
    }
    $archive = [System.IO.Compression.ZipFile]::Open($destination,
        [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $files = Get-ChildItem -LiteralPath $SourceDirectory -File -Recurse |
            Sort-Object { Get-RelativeReleasePath $SourceDirectory $_.FullName }
        foreach ($file in $files) {
            $entryName = Get-RelativeReleasePath $SourceDirectory $file.FullName
            $entry = $archive.CreateEntry($entryName,
                [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0,
                [TimeSpan]::Zero)
            $inputStream = $file.OpenRead()
            $outputStream = $entry.Open()
            try {
                $inputStream.CopyTo($outputStream)
            } finally {
                $outputStream.Dispose()
                $inputStream.Dispose()
            }
        }
    } finally {
        $archive.Dispose()
    }
    return $destination
}

function New-ChecksumFile([string[]]$PackagePaths,
    [string]$DestinationPath) {
    $lines = @($PackagePaths | Sort-Object { Split-Path $_ -Leaf } |
        ForEach-Object {
        $hash = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $(Split-Path $_ -Leaf)"
    })
    [System.IO.File]::WriteAllLines($DestinationPath, $lines,
        [System.Text.Encoding]::ASCII)
}

function Get-BinaryFileVersion([string]$BinaryPath) {
    if (-not (Test-Path -LiteralPath $BinaryPath -PathType Leaf)) {
        throw "Release binary not found: $BinaryPath"
    }
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        $file = Get-Item -LiteralPath $BinaryPath -Force
        $file.Refresh()
        $version = $file.VersionInfo.FileVersion
        if ($version) { return $version }
        Start-Sleep -Milliseconds 100
    }
    throw "Release binary has no file version resource: $BinaryPath"
}

function Normalize-PEMetadata([string]$BinaryPath, [long]$UnixTimestamp) {
    if (($UnixTimestamp -lt 0) -or ($UnixTimestamp -gt [uint32]::MaxValue)) {
        throw "Invalid PE timestamp: $UnixTimestamp"
    }
    $bytes = [System.IO.File]::ReadAllBytes($BinaryPath)
    if (($bytes.Length -lt 256) -or ($bytes[0] -ne 0x4D) -or
        ($bytes[1] -ne 0x5A)) { throw "Invalid PE file: $BinaryPath" }
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
    if (($peOffset -lt 0) -or ($peOffset + 24 -ge $bytes.Length) -or
        ([BitConverter]::ToUInt32($bytes, $peOffset) -ne 0x00004550)) {
        throw "Invalid PE header: $BinaryPath"
    }
    [BitConverter]::GetBytes([uint32]$UnixTimestamp).CopyTo($bytes, $peOffset + 8)
    $sectionCount = [BitConverter]::ToUInt16($bytes, $peOffset + 6)
    $optionalSize = [BitConverter]::ToUInt16($bytes, $peOffset + 20)
    $optionalOffset = $peOffset + 24
    $magic = [BitConverter]::ToUInt16($bytes, $optionalOffset)
    $dataDirectoryOffset = $optionalOffset + 96
    if ($magic -eq 0x20B) { $dataDirectoryOffset = $optionalOffset + 112 }
    if (($magic -ne 0x10B) -and ($magic -ne 0x20B)) {
        throw "Unsupported PE optional header: $BinaryPath"
    }
    $resourceRva = [BitConverter]::ToUInt32($bytes, $dataDirectoryOffset + 16)
    $sectionOffset = $optionalOffset + $optionalSize
    $resourceOffset = -1
    for ($sectionIndex = 0; $sectionIndex -lt $sectionCount; $sectionIndex++) {
        $currentSection = $sectionOffset + ($sectionIndex * 40)
        $virtualSize = [BitConverter]::ToUInt32($bytes, $currentSection + 8)
        $virtualAddress = [BitConverter]::ToUInt32($bytes, $currentSection + 12)
        if (($resourceRva -ge $virtualAddress) -and
            ($resourceRva -lt $virtualAddress + $virtualSize)) {
            $rawOffset = [BitConverter]::ToUInt32($bytes, $currentSection + 20)
            $resourceOffset = [int]($rawOffset + $resourceRva - $virtualAddress)
        }
    }
    if ($resourceOffset -ge 0) {
        $pending = [System.Collections.Generic.Stack[int]]::new()
        $visited = [System.Collections.Generic.HashSet[int]]::new()
        $pending.Push($resourceOffset)
        while ($pending.Count -gt 0) {
            $directoryOffset = $pending.Pop()
            if (-not $visited.Add($directoryOffset)) { continue }
            [BitConverter]::GetBytes([uint32]$UnixTimestamp).CopyTo(
                $bytes, $directoryOffset + 4)
            $namedCount = [BitConverter]::ToUInt16($bytes, $directoryOffset + 12)
            $idCount = [BitConverter]::ToUInt16($bytes, $directoryOffset + 14)
            $entryCount = $namedCount + $idCount
            for ($entryIndex = 0; $entryIndex -lt $entryCount; $entryIndex++) {
                $entryOffset = $directoryOffset + 16 + ($entryIndex * 8)
                $target = [BitConverter]::ToUInt32($bytes, $entryOffset + 4)
                if (($target -band 0x80000000) -ne 0) {
                    $pending.Push($resourceOffset + [int]($target -band 0x7FFFFFFF))
                }
            }
        }
    }
    [System.IO.File]::WriteAllBytes($BinaryPath, $bytes)
}
