param(
    [Parameter(Mandatory = $true)][string]$CliPath,
    [Parameter(Mandatory = $true)][ValidateSet('Win32', 'Win64')][string]$Platform
)

$ErrorActionPreference = 'Stop'
$resolvedCli = (Resolve-Path -LiteralPath $CliPath).Path
$fixture = Join-Path $PSScriptRoot 'Fixtures\LifecycleConsole'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('AtroposLifecycle-' + [Guid]::NewGuid().ToString('N'))

$fixtureHashes = @{}
foreach ($file in Get-ChildItem -LiteralPath $fixture -File) {
    $fixtureHashes[$file.FullName] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
}
function Invoke-CheckedProcess([string]$Executable, [string[]]$Arguments, [string]$Label) {
    $stdout = Join-Path $temporaryRoot ($Label + '.out')
    $stderr = Join-Path $temporaryRoot ($Label + '.err')
    $options = @{
        FilePath = $Executable
        RedirectStandardOutput = $stdout
        RedirectStandardError = $stderr
        PassThru = $true
        WindowStyle = 'Hidden'
    }
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
    $working = Join-Path $temporaryRoot 'LifecycleConsole'
    $project = Join-Path $working 'LifecycleConsole.dproj'
    $consumer = Join-Path $working 'Lifecycle.Consumer.pas'
    $original = (Get-FileHash -LiteralPath $consumer -Algorithm SHA256).Hash
    $arguments = @('-dproj', ('"' + $project + '"'), '--remove', '--move', '--target', "Debug|$Platform")
    Invoke-CheckedProcess $resolvedCli ($arguments + '--dry-run') 'baseline' | Out-Null
    if ((Get-FileHash -LiteralPath $consumer -Algorithm SHA256).Hash -ne $original) {
        throw 'Dry-run changed the lifecycle consumer.'
    }
    $program = Join-Path $working ".artifacts\$Platform\Debug\LifecycleConsole.exe"
    $before = Invoke-CheckedProcess $program @() 'before'
    if ($before -ne 'Boot|Main|Shutdown') { throw "Unexpected original lifecycle: $before" }
    Invoke-CheckedProcess $resolvedCli $arguments 'apply' | Out-Null
    $after = Invoke-CheckedProcess $program @() 'after'
    if ($after -ne $before) { throw "Lifecycle changed: $before -> $after" }
    $source = Get-Content -Raw -LiteralPath $consumer
    if ($source.Contains('Lifecycle.Unused')) { throw 'Unused import was not removed.' }
    $sections = [regex]::new('(?i)\bimplementation\b').Split($source, 2)
    if ($sections.Count -ne 2 -or $sections[0].Contains('Lifecycle.Provider') -or
        -not $sections[1].Contains('Lifecycle.Provider')) {
        throw 'Lifecycle provider was not moved to implementation.'
    }
    foreach ($path in $fixtureHashes.Keys) {
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $fixtureHashes[$path]) {
            throw "Repository lifecycle fixture changed: $path"
        }
    }
    Write-Host "$Platform lifecycle runtime smoke passed: $before -> $after."
}
finally {
    $resolved = [IO.Path]::GetFullPath($temporaryRoot)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolved.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolved -Leaf).StartsWith('AtroposLifecycle-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
