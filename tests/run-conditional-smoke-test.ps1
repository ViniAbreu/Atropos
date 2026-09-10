param(
    [Parameter(Mandatory = $true)][string]$CliPath,
    [Parameter(Mandatory = $true)][ValidateSet('Win32', 'Win64')][string]$Platform
)
$ErrorActionPreference = 'Stop'
$resolvedCli = (Resolve-Path -LiteralPath $CliPath).Path
$fixture = Join-Path $PSScriptRoot 'Fixtures\ConditionalConsole'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('AtroposConditions-' + [Guid]::NewGuid().ToString('N'))
$hashes = @{}
foreach ($file in Get-ChildItem -LiteralPath $fixture -File) {
    $hashes[$file.FullName] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
}
function Invoke-ConditionalProcess([string]$Executable, [string[]]$Arguments, [string]$Label) {
    $stdout = Join-Path $temporaryRoot ($Label + '.out')
    $stderr = Join-Path $temporaryRoot ($Label + '.err')
    $options = @{ FilePath = $Executable; RedirectStandardOutput = $stdout;
        RedirectStandardError = $stderr; PassThru = $true; WindowStyle = 'Hidden' }
    if ($Arguments.Count -gt 0) { $options.ArgumentList = $Arguments }
    $process = Start-Process @options
    if (-not $process.WaitForExit(180000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "$Label timed out."
    }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "$Label failed: $(Get-Content -Raw -LiteralPath $stdout) $(Get-Content -Raw -LiteralPath $stderr)"
    }
    return ((Get-Content -LiteralPath $stdout) -join '|').Trim()
}
try {
    [IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
    Copy-Item -LiteralPath $fixture -Destination $temporaryRoot -Recurse
    $working = Join-Path $temporaryRoot 'ConditionalConsole'
    $project = Join-Path $working 'ConditionalConsole.dproj'
    $consumer = Join-Path $working 'Conditional.Consumer.pas'
    $original = (Get-FileHash -LiteralPath $consumer -Algorithm SHA256).Hash
    $arguments = @('-dproj', ('"' + $project + '"'), '--remove',
        '--target', "Debug|$Platform", '--target', "Release|$Platform")
    Invoke-ConditionalProcess $resolvedCli ($arguments + '--dry-run') 'preview' | Out-Null
    if ((Get-FileHash -LiteralPath $consumer -Algorithm SHA256).Hash -ne $original) {
        throw 'Conditional dry-run changed the source.'
    }
    foreach ($phase in @('before', 'after')) {
        if ($phase -eq 'after') {
            Invoke-ConditionalProcess $resolvedCli $arguments 'apply' | Out-Null
            $source = Get-Content -Raw -LiteralPath $consumer
            if ($source.Contains('Conditional.Unused')) { throw 'Unused import was not removed.' }
            if (-not $source.Contains('Conditional.Chosen') -or -not $source.Contains('Conditional.Other')) {
                throw 'Conditional imports were removed.'
            }
        }
        foreach ($config in @('Debug', 'Release')) {
            $program = Join-Path $working ".artifacts\$Platform\$config\ConditionalConsole.exe"
            $actual = Invoke-ConditionalProcess $program @() "$phase-$config"
            $expected = 'Precedence|100|Include'
            if ($config -eq 'Debug') { $expected = 'Precedence|8|Include' }
            if ($actual -ne $expected) { throw "Unexpected $phase $config output: $actual" }
        }
    }
    foreach ($path in $hashes.Keys) {
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $hashes[$path]) {
            throw "Repository fixture changed: $path"
        }
    }
    Write-Host "$Platform conditional runtime passed: Debug Precedence|8|Include, Release Precedence|100|Include."
}
finally {
    $resolved = [IO.Path]::GetFullPath($temporaryRoot)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolved.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolved -Leaf).StartsWith('AtroposConditions-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
