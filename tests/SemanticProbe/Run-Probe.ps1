[CmdletBinding()]
param(
    [string]$Executable = (Join-Path $PSScriptRoot 'bin/Win32/Base/Probe.exe'),
    [string]$Category = '*',
    [string]$Case = '*',
    [ValidateRange(1, 100)][int]$Repeat = 1,
    [ValidateRange(1, 600)][int]$TimeoutSeconds = 30,
    [switch]$ValidateOnly,
    [string]$Baseline = (Join-Path $PSScriptRoot 'baselines/research-20260909.json')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Probe.Tools.ps1')

function Read-Json([string]$Path) {
    Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Get-Property($Object, [string]$Name, $Default = $null) {
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Resolve-Input([string]$RelativePath) {
    $resolved = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $RelativePath))
    if (-not (Test-Path -LiteralPath $resolved)) { throw "Missing input: $resolved" }
    return $resolved
}

function Invoke-Probe([string]$Arguments) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $script:probePath
    $start.Arguments = $Arguments
    $start.WorkingDirectory = $PSScriptRoot
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $process.StandardInput.Close()
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            $process.WaitForExit()
            throw "Probe timeout after $TimeoutSeconds seconds"
        }
        $output = $outputTask.GetAwaiter().GetResult()
        $errorText = $errorTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "Probe exit $($process.ExitCode): $output $errorText" }
        return $output.Trim()
    }
    finally { $process.Dispose() }
}

function New-Request($Scenario, [string]$CaseDirectory) {
    $request = [ordered]@{ consumer = (Resolve-Input $Scenario.consumer); dependencies = @() }
    foreach ($dependency in @(Get-Property $Scenario 'dependencies' @())) {
        $request.dependencies += @{path=(Resolve-Input $dependency.path); native=[bool](Get-Property $dependency 'native' $false)}
    }
    foreach ($key in @('resolver','rewrite','removeEnabled','moveEnabled','changes')) {
        $value = Get-Property $Scenario $key
        if ($null -ne $value) { $request[$key] = $value }
    }
    $request.searchPaths = @()
    foreach ($searchPath in @(Get-Property $Scenario 'searchPaths' @())) {
        $request.searchPaths += Resolve-Input $searchPath
    }
    return $request
}

function Compare-Check($Observation, $Check) {
    $actualProperty = $Observation.PSObject.Properties[$Check.field]
    if ($null -eq $actualProperty) { return $false }
    $actual = $actualProperty.Value
    $expected = $Check.value
    $operation = $Check.op
    $actualList = @($actual)
    $expectedList = @($expected)
    if ($operation -eq 'set') {
        $left = @($actualList | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique)
        $right = @($expectedList | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique)
        return ($null -ne $actual -and ($left -join "`n") -ceq ($right -join "`n"))
    }
    if ($operation -eq 'contains') { return ($null -ne $actual -and $actualList -contains $expected) }
    if ($operation -eq 'excludes') { return ($null -ne $actual -and $actualList -notcontains $expected) }
    if ($operation -eq 'match') { return ($null -ne $actual -and [string]$actual -cmatch [string]$expected) }
    if ($operation -eq 'notMatch') { return ($null -ne $actual -and [string]$actual -cnotmatch [string]$expected) }
    if ($operation -eq 'count') { return ($null -ne $actual -and $actualList.Count -eq [int]$expected) }
    if ($operation -eq 'equals') { return ($null -ne $actual -and $actual -ceq $expected) }
    throw "Unknown comparison: $operation"
}

function Test-Scenario($Scenario, $Observation) {
    $failures = @()
    foreach ($check in $Scenario.checks) {
        if (Compare-Check $Observation $check) { continue }
        $actual = Get-Property $Observation $check.field
        $failures += "$($check.field) $($check.op): expected $($check.value | ConvertTo-Json -Compress -Depth 10); actual $($actual | ConvertTo-Json -Compress -Depth 10)"
    }
    return $failures
}

function Get-TimingSummary($Samples) {
    $values = @($Samples | Where-Object { $null -ne $_.totalMs } | ForEach-Object { [double]$_.totalMs } | Sort-Object)
    if ($values.Count -eq 0) { return $null }
    $median = $values[[int][Math]::Floor($values.Count / 2)]
    if ($values.Count % 2 -eq 0) { $median = ($values[$values.Count / 2 - 1] + $values[$values.Count / 2]) / 2 }
    $percentileIndex = [int][Math]::Ceiling($values.Count * 0.95) - 1
    return [pscustomobject]@{medianTotalMs=$median;p95TotalMs=$values[$percentileIndex];samples=$values.Count}
}

$manifestPath = Join-Path $PSScriptRoot 'scenarios/catalog.json'
$manifest = Read-Json $manifestPath
$all = @($manifest.scenarios)
$duplicates = @($all | Group-Object id | Where-Object Count -gt 1)
if ($duplicates.Count -gt 0) { throw 'Duplicate scenario IDs' }
$allowedOperations = @('set','contains','excludes','match','notMatch','count','equals')
foreach ($scenario in $all) {
    if ($scenario.id -notmatch '^[a-z0-9-]+$') { throw "Invalid ID: $($scenario.id)" }
    if ($scenario.kind -eq 'blocked') {
        if (-not $scenario.reason) { throw 'Blocked case requires a reason' }
        $null = Resolve-Input $scenario.consumer
        continue
    }
    if ($scenario.checks.Count -eq 0) { throw "No oracle: $($scenario.id)" }
    foreach ($check in $scenario.checks) {
        if ($allowedOperations -notcontains $check.op) { throw "Invalid check in $($scenario.id)" }
    }
    $null = New-Request $scenario $PSScriptRoot
}
$selected = @($all | Where-Object { $_.category -like $Category -and $_.id -like $Case })
if ($selected.Count -eq 0) { throw 'No scenarios selected' }
Write-Host "Catalog valid: $($all.Count) scenarios; selected: $($selected.Count)"
if ($ValidateOnly) { exit 0 }

$script:probePath = (Resolve-Path -LiteralPath $Executable).Path
if ((Invoke-Probe '--protocol') -ne '2') { throw 'Run Build-Probe.ps1: executable requires protocol 2.' }
$buildManifest = Read-Json "$script:probePath.build.json"
if ($buildManifest.schemaVersion -ne 1) { throw 'Unsupported build manifest.' }
Assert-ProbeSourceHashes $buildManifest.sourceHashes @(Get-ProbeSourceHashes $PSScriptRoot)
if ((Get-FileHash -LiteralPath $script:probePath -Algorithm SHA256).Hash -ne $buildManifest.executableSha256) {
    throw 'Probe binary differs from its build manifest. Run Build-Probe.ps1.'
}
$runPath = Join-Path $PSScriptRoot ('results/' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
[void](New-Item -ItemType Directory -Path $runPath)
$sourceHashes = @(Get-ChildItem (Join-Path $PSScriptRoot 'scenarios') -Recurse -File | Get-FileHash -Algorithm SHA256)
$results = @()
foreach ($scenario in $selected) {
    if ($scenario.kind -eq 'blocked') {
        $results += [pscustomobject]@{id=$scenario.id;category=$scenario.category;status='BLOCKED';failures=@($scenario.reason);samples=@()}
        Write-Host "BLOCKED $($scenario.id)"
        continue
    }
    $casePath = Join-Path $runPath $scenario.id
    [void](New-Item -ItemType Directory -Path $casePath)
    $request = New-Request $scenario $casePath
    $requestPath = Join-Path $casePath 'request.json'
    $request | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $requestPath -Encoding UTF8
    $failures = @()
    $samples = @()
    $status = 'PASS'
    for ($iteration = 1; $iteration -le $Repeat; $iteration++) {
        $observationPath = Join-Path $casePath "observation-$iteration.json"
        try {
            $null = Invoke-Probe ('--case "{0}" "{1}"' -f $requestPath, $observationPath)
            $observation = Read-Json $observationPath
            if ((Get-Property $observation 'protocol') -ne 2) { throw 'Invalid observation protocol.' }
            $sampleFailures = @(Test-Scenario $scenario $observation)
            $failures += $sampleFailures
            if ($sampleFailures.Count -gt 0 -and $status -ne 'ERROR') { $status = 'FAIL' }
            $samples += [pscustomobject]@{parseMs=(Get-Property $observation 'parseMs');extractMs=(Get-Property $observation 'extractMs');totalMs=(Get-Property $observation 'totalMs')}
        }
        catch { $status = 'ERROR'; $failures += $_.Exception.Message }
    }
    $results += [pscustomobject]@{id=$scenario.id;category=$scenario.category;status=$status;failures=@($failures | Select-Object -Unique);samples=$samples;timing=(Get-TimingSummary $samples)}
    Write-Host "$status $($scenario.id)"
}
foreach ($hash in $sourceHashes) {
    if ((Get-FileHash -LiteralPath $hash.Path -Algorithm SHA256).Hash -ne $hash.Hash) { throw "Fixture changed: $($hash.Path)" }
}
Assert-ProbeSourceHashes $buildManifest.sourceHashes @(Get-ProbeSourceHashes $PSScriptRoot)
$summary = [ordered]@{
    protocol=2; createdUtc=[DateTime]::UtcNow.ToString('o'); executable=$script:probePath
    build=$buildManifest
    runnerSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
    executableSha256=(Get-FileHash -LiteralPath $script:probePath -Algorithm SHA256).Hash
    catalogSha256=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
    fixtureHashes=$sourceHashes
    repeat=$Repeat; total=$results.Count
    passed=@($results | Where-Object status -eq 'PASS').Count
    failed=@($results | Where-Object status -eq 'FAIL').Count
    errors=@($results | Where-Object status -eq 'ERROR').Count
    blocked=@($results | Where-Object status -eq 'BLOCKED').Count
    results=$results
}
if ($Baseline) {
    $previous = Read-Json $Baseline
    $summary['comparisonBaselineSha256'] = (Get-FileHash -LiteralPath $Baseline -Algorithm SHA256).Hash
    $summary['sameCatalogAsBaseline'] = ($previous.catalogSha256 -eq $summary.catalogSha256)
    $changes = @()
    foreach ($result in $results) {
        $prior = @($previous.results | Where-Object id -eq $result.id)
        if ($prior.Count -ne 1) { continue }
        if ($prior[0].status -eq $result.status) { continue }
        $changes += [pscustomobject]@{id=$result.id;before=$prior[0].status;after=$result.status}
    }
    $summary['changes'] = $changes
}
$summary | ConvertTo-Json -Depth 25 | Set-Content (Join-Path $runPath 'summary.json') -Encoding UTF8
$results | Select-Object id,category,status,@{n='failures';e={$_.failures -join ' | '}} | Export-Csv (Join-Path $runPath 'summary.csv') -NoTypeInformation -Encoding UTF8
Write-Host "PASS=$($summary.passed) FAIL=$($summary.failed) ERROR=$($summary.errors) BLOCKED=$($summary.blocked)"
Write-Host "Results: $runPath"
if ($summary.errors -gt 0) { exit 2 }
if ($summary.failed -gt 0) { exit 1 }
if ($summary.blocked -gt 0) { exit 3 }
exit 0
