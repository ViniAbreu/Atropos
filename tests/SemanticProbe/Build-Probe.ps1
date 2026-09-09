[CmdletBinding()]
param(
    [string]$BdsPath = 'C:\Program Files (x86)\Embarcadero\Studio\23.0',
    [ValidateSet('Win32', 'Win64')][string]$Platform = 'Win32',
    [ValidateSet('Base', 'Debug', 'Release')][string]$Configuration = 'Base'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Probe.Tools.ps1')
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$rsvars = Join-Path $BdsPath 'bin/rsvars.bat'
$msbuild = Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/MSBuild.exe'
$project = Join-Path $PSScriptRoot 'Probe.dproj'
foreach ($path in @($rsvars, $msbuild, $project)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing build input: $path" }
    if ($path -match '["%\r\n]') { throw 'Build paths cannot contain quotes, percent signs or newlines.' }
}
$inputs = @(Get-ProbeSourceHashes $PSScriptRoot)
$command = '"{0}" && "{1}" "{2}" /t:Build /p:Config={3} /p:Platform={4} /nologo /v:minimal' -f $rsvars, $msbuild, $project, $Configuration, $Platform
& cmd.exe /d /c $command
if ($LASTEXITCODE -ne 0) { throw "Probe build failed: $LASTEXITCODE" }
Assert-ProbeSourceHashes $inputs @(Get-ProbeSourceHashes $PSScriptRoot)
$executable = Join-Path $PSScriptRoot "bin/$Platform/$Configuration/Probe.exe"
$infoText = & $executable --build-info
if ($LASTEXITCODE -ne 0) { throw 'Cannot read Probe build information.' }
$info = $infoText | ConvertFrom-Json
if ($info.platform -ne $Platform) { throw 'Built executable has an unexpected architecture.' }
$manifest = [ordered]@{
    schemaVersion=1
    createdUtc=[DateTime]::UtcNow.ToString('o')
    repositoryCommit=(Get-ProbeGitRevision $repository)
    delphiAstCommit=(Get-ProbeGitRevision (Join-Path $repository 'third_party/DelphiAST'))
    workingTreeStatus=@(& git -C $repository status --porcelain --untracked-files=normal)
    configuration=$Configuration
    toolchain=$info
    bdsPath=$BdsPath
    executableSha256=(Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash
    sourceHashes=$inputs
}
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath "$executable.build.json" -Encoding UTF8
Write-Host "Built $executable with recorded source hashes."
