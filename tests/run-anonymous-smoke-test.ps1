param(
    [Parameter(Mandatory = $true)][string]$CliPath,
    [Parameter(Mandatory = $true)][ValidateSet('Win32', 'Win64')][string]$Platform,
    [string]$BdsVersion = '23.0'
)
$ErrorActionPreference = 'Stop'
$resolvedCli = (Resolve-Path -LiteralPath $CliPath).Path
$fixture = Join-Path $PSScriptRoot 'Fixtures\AnonymousConsole'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('AtroposAnonymous-' + [Guid]::NewGuid().ToString('N'))
$hashes = @{}
$historicalConsumer = Join-Path $PSScriptRoot 'SemanticProbe\scenarios\anonymous-parameter-shadow\Consumer.pas'
$historicalProvider = Join-Path $PSScriptRoot 'SemanticProbe\scenarios\providers\ProbeDep.pas'
foreach ($path in @((Get-ChildItem -LiteralPath $fixture -File).FullName) + @($historicalConsumer, $historicalProvider)) {
    $hashes[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
function Invoke-AnonymousProcess([string]$Executable, [string[]]$Arguments, [string]$Label, [bool]$ExpectRejection = $false) {
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
    $output = ((Get-Content -LiteralPath $stdout) -join '|').Trim()
    if ($ExpectRejection) {
        if ($process.ExitCode -eq 0 -or $output -notmatch "E2003.*reference") {
            throw "Historical inline reference-to syntax was not rejected as expected: $output"
        }
        return $output
    }
    if ($process.ExitCode -ne 0) {
        throw "$Label failed: $output $(Get-Content -Raw -LiteralPath $stderr)"
    }
    return $output
}
try {
    [IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
    $negative = Join-Path $temporaryRoot 'historical'
    [IO.Directory]::CreateDirectory($negative) | Out-Null
    Copy-Item -LiteralPath $historicalConsumer, $historicalProvider -Destination $negative
    $compilerName = 'dcc32.exe'
    if ($Platform -eq 'Win64') { $compilerName = 'dcc64.exe' }
    $compiler = Join-Path ${env:ProgramFiles(x86)} "Embarcadero\Studio\$BdsVersion\bin\$compilerName"
    Invoke-AnonymousProcess $compiler @('-U"' + $negative + '"', '"' + (Join-Path $negative 'Consumer.pas') + '"') 'historical' $true | Out-Null
    Copy-Item -LiteralPath $fixture -Destination $temporaryRoot -Recurse
    $working = Join-Path $temporaryRoot 'AnonymousConsole'
    $project = Join-Path $working 'AnonymousConsole.dproj'
    $consumer = Join-Path $working 'Anonymous.Consumer.pas'
    $arguments = @('-dproj', ('"' + $project + '"'), '--remove', '--target', "Debug|$Platform")
    $original = (Get-FileHash -LiteralPath $consumer -Algorithm SHA256).Hash
    Invoke-AnonymousProcess $resolvedCli ($arguments + '--dry-run') 'preview' | Out-Null
    if ((Get-FileHash -LiteralPath $consumer -Algorithm SHA256).Hash -ne $original) {
        throw 'Anonymous-method dry-run changed the source.'
    }
    $program = Join-Path $working ".artifacts\$Platform\Debug\AnonymousConsole.exe"
    $expected = 'Parameter:2|Capture:11|Global:1|Outside:99'
    if ((Invoke-AnonymousProcess $program @() 'before') -ne $expected) { throw 'Unexpected initial anonymous-method behavior.' }
    Invoke-AnonymousProcess $resolvedCli $arguments 'apply' | Out-Null
    $source = Get-Content -Raw -LiteralPath $consumer
    if ($source.Contains('Anonymous.Shadow')) { throw 'Shadowed dependency was not removed.' }
    if (-not $source.Contains('Anonymous.Global')) { throw 'Captured global dependency was removed.' }
    if (-not (Get-Content -Raw -LiteralPath (Join-Path $working 'Anonymous.Leak.pas')).Contains('Anonymous.Shadow')) {
        throw 'Anonymous parameter scope leaked into the containing routine.'
    }
    if ((Invoke-AnonymousProcess $program @() 'after') -ne $expected) { throw 'Anonymous-method behavior changed.' }
    foreach ($path in $hashes.Keys) {
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $hashes[$path]) {
            throw "Versioned fixture changed: $path"
        }
    }
    Write-Host "$Platform anonymous runtime passed: historical syntax rejected; $expected before/after."
}
finally {
    $resolved = [IO.Path]::GetFullPath($temporaryRoot)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolved.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolved -Leaf).StartsWith('AtroposAnonymous-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
