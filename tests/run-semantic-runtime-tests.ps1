param(
    [Parameter(Mandatory = $true)][string]$CliPath,
    [Parameter(Mandatory = $true)][ValidateSet('Win32', 'Win64')][string]$Platform,
    [string]$EvidenceDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\integration')
)
$ErrorActionPreference = 'Stop'
$resolvedCli = (Resolve-Path -LiteralPath $CliPath).Path
$fixture = Join-Path $PSScriptRoot 'Fixtures\SemanticRuntime'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('AtroposRuntime-' + [Guid]::NewGuid().ToString('N'))
$evidenceRoot = Join-Path $EvidenceDirectory $Platform
[IO.Directory]::CreateDirectory($evidenceRoot) | Out-Null
$evidencePath = Join-Path $evidenceRoot 'semantic-runtime.json'
$hashes = @{}
foreach ($file in Get-ChildItem -LiteralPath $fixture -File) {
    $hashes[$file.Name] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
}
$evidence = [ordered]@{
    schemaVersion = 1; status = 'RUNNING'; target = "Debug|$Platform"
    startedUtc = [DateTime]::UtcNow.ToString('o'); cliPath = $resolvedCli
    runnerSha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
    cliSha256 = (Get-FileHash -LiteralPath $resolvedCli -Algorithm SHA256).Hash
    researchCatalogSha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'SemanticProbe\scenarios\catalog.json') -Algorithm SHA256).Hash
    fixtureHashes = $hashes; contracts = @(); observations = @{}
}
$evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidencePath -Encoding utf8NoBOM
function Invoke-RuntimeProcess([string]$Executable, [string[]]$Arguments, [string]$Label) {
    $stdout = Join-Path $evidenceRoot ($Label + '.out')
    $stderr = Join-Path $evidenceRoot ($Label + '.err')
    $options = @{ FilePath = $Executable; RedirectStandardOutput = $stdout;
        RedirectStandardError = $stderr; PassThru = $true; WindowStyle = 'Hidden' }
    if ($Arguments.Count -gt 0) { $options.ArgumentList = $Arguments }
    $process = Start-Process @options
    if (-not $process.WaitForExit(180000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "$Label timed out."
    }
    $process.WaitForExit()
    return [pscustomobject]@{
        exitCode = $process.ExitCode
        output = ((Get-Content -LiteralPath $stdout) -join '|').Trim()
        errorOutput = ((Get-Content -LiteralPath $stderr) -join '|').Trim()
    }
}
function Copy-RuntimeFixture([string]$Name) {
    $directory = Join-Path $temporaryRoot $Name
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    Copy-Item -LiteralPath $fixture -Destination $directory -Recurse
    return (Join-Path $directory 'SemanticRuntime')
}
function Invoke-RuntimeCleaner([string]$Working, [string]$Label, [bool]$DryRun) {
    $project = Join-Path $Working 'SemanticRuntime.dproj'
    $arguments = @('-dproj', ('"' + $project + '"'), '--remove', '--move', '--target', "Debug|$Platform")
    if ($DryRun) { $arguments += '--dry-run' }
    $result = Invoke-RuntimeProcess $resolvedCli $arguments $Label
    if ($result.exitCode -ne 0) { throw "$Label failed: $($result.output) $($result.errorOutput)" }
}
function Invoke-RuntimeProgram([string]$Working, [string]$Label) {
    return Invoke-RuntimeProcess (Join-Path $Working ".artifacts\$Platform\Debug\SemanticRuntime.exe") @() $Label
}
try {
    $working = Copy-RuntimeFixture 'positive'
    foreach ($name in @('Semantic.Form.pas', 'Semantic.Calls.pas')) {
        if (-not (Get-Content -Raw -LiteralPath (Join-Path $working $name)).Contains('Semantic.Unused')) {
            throw "Fixture $name has no unused import to exercise removal."
        }
    }
    Invoke-RuntimeCleaner $working 'preview' $true
    foreach ($name in $hashes.Keys) {
        if ((Get-FileHash -LiteralPath (Join-Path $working $name) -Algorithm SHA256).Hash -ne $hashes[$name]) {
            throw "Dry-run changed $name."
        }
    }
    $expected = 'DFM:42|Registry:TStreamProbe|Integer|String'
    $before = Invoke-RuntimeProgram $working 'before'
    if ($before.exitCode -ne 0 -or $before.output -ne $expected) { throw "Unexpected initial behavior: $($before.output)" }
    Invoke-RuntimeCleaner $working 'apply' $false
    $diagnostics = Get-Content -Raw -LiteralPath (Join-Path $evidenceRoot 'apply.out')
    if ($diagnostics.Contains('Conflicting decisions for the same import occurrence')) {
        throw 'A preserved dependency was incorrectly reported as conflicting.'
    }
    if ($diagnostics -notmatch 'Semantic.Overloads.*ambiguous.*Pick') {
        throw 'The overload preservation reason was not reported.'
    }
    $form = Get-Content -Raw -LiteralPath (Join-Path $working 'Semantic.Form.pas')
    $calls = Get-Content -Raw -LiteralPath (Join-Path $working 'Semantic.Calls.pas')
    if ($form.Contains('Semantic.Unused') -or $calls.Contains('Semantic.Unused')) { throw 'Unused imports were not removed.' }
    if (-not $form.Contains('Semantic.Registration')) { throw 'Dynamic registration dependency was removed.' }
    if (-not $calls.Contains('Semantic.Overloads, Semantic.Fallback')) { throw 'Overload candidates changed order or were removed.' }
    if ((Get-FileHash -LiteralPath (Join-Path $working 'Semantic.Form.dfm') -Algorithm SHA256).Hash -ne $hashes['Semantic.Form.dfm']) {
        throw 'DFM resource changed during cleanup.'
    }
    $after = Invoke-RuntimeProgram $working 'after'
    if ($after.exitCode -ne 0 -or $after.output -ne $expected) { throw "Semantic behavior changed: $($after.output)" }
    $evidence.observations.before = $before
    $evidence.observations.after = $after

    $unregistered = Copy-RuntimeFixture 'unregistered'
    $path = Join-Path $unregistered 'Semantic.Form.pas'
    $source = [IO.File]::ReadAllText($path)
    if (-not $source.Contains(', Semantic.Registration')) { throw 'Registration negative control did not match.' }
    [IO.File]::WriteAllText($path, $source.Replace(', Semantic.Registration', ''), [Text.UTF8Encoding]::new($false))
    Invoke-RuntimeCleaner $unregistered 'unregistered-build' $true
    $missing = Invoke-RuntimeProgram $unregistered 'unregistered-run'
    if ($missing.exitCode -eq 0 -or $missing.output -notmatch 'ERROR:(EClassNotFound|EReadError):.*TStreamProbe') {
        throw "Missing registration did not fail during streaming: $($missing.output)"
    }
    $evidence.observations.missingRegistration = $missing

    $fallback = Copy-RuntimeFixture 'fallback'
    $path = Join-Path $fallback 'Semantic.Calls.pas'
    $source = [IO.File]::ReadAllText($path)
    if (-not $source.Contains('Semantic.Overloads, ')) { throw 'Overload negative control did not match.' }
    [IO.File]::WriteAllText($path, $source.Replace('Semantic.Overloads, ', ''), [Text.UTF8Encoding]::new($false))
    Invoke-RuntimeCleaner $fallback 'fallback-build' $true
    $changed = Invoke-RuntimeProgram $fallback 'fallback-run'
    if ($changed.exitCode -ne 0 -or $changed.output -ne 'DFM:42|Registry:TStreamProbe|Variant|Variant') {
        throw "Overload negative control did not expose changed binding: $($changed.output)"
    }
    $evidence.observations.changedOverload = $changed
    foreach ($name in $hashes.Keys) {
        if ((Get-FileHash -LiteralPath (Join-Path $fixture $name) -Algorithm SHA256).Hash -ne $hashes[$name]) {
            throw "Versioned fixture changed: $name"
        }
    }
    $evidence.contracts = @('dfm-streaming-registration', 'rtti-string-registration', 'compiler-overload-binding') |
        ForEach-Object { [ordered]@{ id = $_; status = 'PASS' } }
    $evidence.status = 'PASS'
    Write-Host "$Platform semantic runtime passed: $expected; both negative controls confirmed."
}
catch {
    $evidence.status = 'FAIL'
    $evidence.failure = $_.Exception.Message
    throw
}
finally {
    $evidence.finishedUtc = [DateTime]::UtcNow.ToString('o')
    $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidencePath -Encoding utf8NoBOM
    $resolved = [IO.Path]::GetFullPath($temporaryRoot)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolved.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolved -Leaf).StartsWith('AtroposRuntime-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
