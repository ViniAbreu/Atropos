param(
    [Parameter(Mandatory = $true)][string]$CliPath,
    [Parameter(Mandatory = $true)][ValidateSet('Win32', 'Win64')][string]$Platform
)

$ErrorActionPreference = 'Stop'
$resolvedCli = (Resolve-Path -LiteralPath $CliPath).Path
$fixture = Join-Path $PSScriptRoot 'Fixtures\UsesConsole'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('AtroposUses-' + [Guid]::NewGuid().ToString('N'))
$fixtureHashes = @{}
foreach ($file in Get-ChildItem -LiteralPath $fixture -File) {
    $fixtureHashes[$file.FullName] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
}
function Invoke-UsesProcess([string]$Executable, [string[]]$Arguments, [string]$Label) {
    $stdout = Join-Path $temporaryRoot ($Label + '.out')
    $stderr = Join-Path $temporaryRoot ($Label + '.err')
    $options = @{
        FilePath = $Executable; RedirectStandardOutput = $stdout
        RedirectStandardError = $stderr; PassThru = $true; WindowStyle = 'Hidden'
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
    $working = Join-Path $temporaryRoot 'UsesConsole'
    $project = Join-Path $working 'UsesConsole.dproj'
    $consumer = Join-Path $working 'Edit.Consumer.pas'
    $original = (Get-FileHash -LiteralPath $consumer -Algorithm SHA256).Hash
    $arguments = @('-dproj', ('"' + $project + '"'), '--remove', '--move',
        '--target', "Debug|$Platform", '--target', "Release|$Platform")
    Invoke-UsesProcess $resolvedCli ($arguments + '--dry-run') 'preview' | Out-Null
    if ((Get-FileHash -LiteralPath $consumer -Algorithm SHA256).Hash -ne $original) {
        throw 'Dry-run changed the source.'
    }
    $before = @{}
    foreach ($config in @('Debug', 'Release')) {
        $program = Join-Path $working ".artifacts\$Platform\$config\UsesConsole.exe"
        $before[$config] = Invoke-UsesProcess $program @() "before-$config"
        $expected = '7'
        if ($config -eq 'Debug') { $expected = 'Extra|7' }
        if ($before[$config] -ne $expected) { throw "Unexpected $config output: $($before[$config])" }
    }
    Invoke-UsesProcess $resolvedCli $arguments 'apply' | Out-Null
    $source = Get-Content -Raw -LiteralPath $consumer
    if ($source.Contains('Edit.Unused')) { throw 'Unused import was not removed.' }
    $sections = [regex]::new('(?i)\bimplementation\b').Split($source, 2)
    if ($sections[0].Contains('Edit.Value') -or -not $sections[1].Contains('uses Edit.Value')) {
        throw 'Provider was not moved into the guarded destination.'
    }
    if (-not $source.Contains('(*$IFDEF WITH_EXTRA*)') -or -not $source.Contains('(*$ENDIF*)')) {
        throw 'Parenthesized conditional directives changed.'
    }
    foreach ($config in @('Debug', 'Release')) {
        $program = Join-Path $working ".artifacts\$Platform\$config\UsesConsole.exe"
        $after = Invoke-UsesProcess $program @() "after-$config"
        if ($after -ne $before[$config]) { throw "$config behavior changed: $($before[$config]) -> $after" }
    }
    $edited = (Get-FileHash -LiteralPath $consumer -Algorithm SHA256).Hash
    Invoke-UsesProcess $resolvedCli $arguments 'repeat' | Out-Null
    if ((Get-FileHash -LiteralPath $consumer -Algorithm SHA256).Hash -ne $edited) {
        throw 'A repeated execution changed the source bytes.'
    }
    foreach ($path in $fixtureHashes.Keys) {
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $fixtureHashes[$path]) {
            throw "Repository fixture changed: $path"
        }
    }
    Write-Host "$Platform uses-edit runtime passed: Debug Extra|7, Release 7; repeat unchanged."
}
finally {
    $resolved = [IO.Path]::GetFullPath($temporaryRoot)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolved.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolved -Leaf).StartsWith('AtroposUses-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
