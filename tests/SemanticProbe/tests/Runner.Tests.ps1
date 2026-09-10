$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$runner = Join-Path $PSScriptRoot '../Run-Probe.ps1'
$tokens = $null
$parseErrors = $null
$syntax = [Management.Automation.Language.Parser]::ParseFile($runner, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
# Load only the pure comparison functions, without launching the suite.
$functions = $syntax.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]}, $true)
foreach ($function in $functions) {
    if ($function.Name -notin @('Get-Property', 'Compare-Check', 'Test-Scenario')) { continue }
    . ([scriptblock]::Create($function.Extent.Text))
}
$tests = @(
    @{actual=@();op='set';expected=@();pass=$true},
    @{actual=@('A');op='set';expected=@();pass=$false},
    @{actual=@('a','B','a');op='set';expected=@('b','A');pass=$true},
    @{actual=@('A');op='contains';expected='A';pass=$true},
    @{actual=@();op='contains';expected='A';pass=$false},
    @{actual=@();op='excludes';expected='A';pass=$true},
    @{actual=@('A');op='excludes';expected='A';pass=$false},
    @{actual=@();op='count';expected=0;pass=$true},
    @{actual=@('A');op='count';expected=1;pass=$true},
    @{actual='ok';op='equals';expected='ok';pass=$true},
    @{actual=$false;op='equals';expected=$false;pass=$true},
    @{actual='uses A;';op='match';expected='uses\s+A;';pass=$true},
    @{actual='uses A;';op='notMatch';expected='uses B;';pass=$true}
)
foreach ($test in $tests) {
    $observation = [pscustomobject]@{value=$test.actual}
    $check = [pscustomobject]@{field='value';op=$test.op;value=$test.expected}
    $result = Compare-Check $observation $check
    if ($result -ne $test.pass) { throw "Comparison failed: $($test | ConvertTo-Json -Compress)" }
}
$missing = Compare-Check ([pscustomobject]@{}) ([pscustomobject]@{field='value';op='set';value=@()})
if ($missing) { throw 'Absent field was accepted as an empty array' }
Write-Output "$($tests.Count + 1) runner checks passed; PowerShell syntax valid."

. (Join-Path $PSScriptRoot '../Probe.Tools.ps1')
$hashes = @([pscustomobject]@{path='src/sample.pas';sha256='ABC'})
Assert-ProbeSourceHashes $hashes $hashes
foreach ($different in @(
    @([pscustomobject]@{path='src/sample.pas';sha256='DEF'}),
    @([pscustomobject]@{path='src/renamed.pas';sha256='ABC'}),
    @()
)) {
    $rejected = $false
    try { Assert-ProbeSourceHashes $hashes $different }
    catch { $rejected = $true }
    if (-not $rejected) { throw 'Source provenance mismatch was accepted.' }
}
$case = [pscustomobject]@{checks=@([pscustomobject]@{field='status';op='equals';value='error'})}
if (@(Test-Scenario $case ([pscustomobject]@{status='error'})).Count -ne 0) {
    throw 'An expected parser error should satisfy its explicit negative oracle.'
}
if (@(Test-Scenario $case ([pscustomobject]@{status='ok'})).Count -ne 1) {
    throw 'Unexpected parser success should fail a negative oracle.'
}
Write-Output 'Source provenance and negative-oracle checks passed.'
