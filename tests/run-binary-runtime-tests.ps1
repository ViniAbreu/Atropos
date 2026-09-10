param(
    [Parameter(Mandatory=$true)][string]$CliPath,
    [Parameter(Mandatory=$true)][ValidateSet('Win32','Win64')][string]$Platform,
    [string]$BdsVersion='23.0'
)
$ErrorActionPreference='Stop'
$cli=(Resolve-Path -LiteralPath $CliPath).Path
$fixture=Join-Path $PSScriptRoot 'Fixtures/BinaryRuntime'
$output=Join-Path (Split-Path $PSScriptRoot -Parent) "artifacts/integration/$Platform/binary-runtime"
$root=Join-Path $output ('work/'+[Guid]::NewGuid().ToString('N'))
$working=Join-Path $root 'BinaryRuntime'
$producer=Join-Path ([IO.Path]::GetTempPath()) ('AtroposBinaryProducer-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($producer) | Out-Null
[IO.Directory]::CreateDirectory($root) | Out-Null
Copy-Item -LiteralPath $fixture -Destination $root -Recurse
$binary=Join-Path $working 'binary'
[IO.Directory]::CreateDirectory($binary) | Out-Null
$bds="C:\Program Files (x86)\Embarcadero\Studio\$BdsVersion"
$compilerName='dcc32.exe'; if($Platform -eq 'Win64'){$compilerName='dcc64.exe'}
$compiler=Join-Path $bds "bin/$compilerName"
$hashes=@{}
foreach($file in Get-ChildItem -LiteralPath $fixture -File){$hashes[$file.Name]=(Get-FileHash -LiteralPath $file.FullName).Hash}
$evidence=[ordered]@{status='RUNNING'; target="Debug|$Platform"; startedUtc=[DateTime]::UtcNow.ToString('o');
    runnerSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash; cliSha256=(Get-FileHash -LiteralPath $cli).Hash;
    compilerSha256=(Get-FileHash -LiteralPath $compiler).Hash;
    catalogSha256=(Get-FileHash (Join-Path $PSScriptRoot 'SemanticProbe/scenarios/catalog.json')).Hash;
    fixtureHashes=$hashes; workingDirectory=$root; producerDirectory=$producer; observations=@{}; contracts=@()}
$evidencePath=Join-Path $output 'result.json'
$evidence | ConvertTo-Json -Depth 8 | Set-Content $evidencePath -Encoding utf8NoBOM
function Invoke-BinaryProcess([string]$Executable,[string[]]$Arguments,[string]$Label){
    $stdout=Join-Path $output "$Label.out"; $stderr=Join-Path $output "$Label.err"
    $options=@{FilePath=$Executable; PassThru=$true; WindowStyle='Hidden'; RedirectStandardOutput=$stdout; RedirectStandardError=$stderr}
    if($Arguments.Count -gt 0){$options.ArgumentList=$Arguments}
    $process=Start-Process @options
    if(-not $process.WaitForExit(180000)){Stop-Process -Id $process.Id -Force; throw "$Label timed out"}
    $process.WaitForExit()
    $text=((Get-Content $stdout) -join '|').Trim()
    if($process.ExitCode -ne 0){throw "$Label failed: $text $(Get-Content $stderr -Raw)"}
    return $text
}
function Invoke-BinaryCleaner([string]$Directory,[string]$Label,[bool]$DryRun){
    $arguments=@('-dproj',('"'+(Join-Path $Directory 'BinaryRuntime.dproj')+'"'),'--remove','--move','--target',"Debug|$Platform")
    if($DryRun){$arguments+='--dry-run'}
    Invoke-BinaryProcess $cli $arguments $Label | Out-Null
}
function Assert-BinaryInputs([string]$Directory) {
    if(@(Get-ChildItem -LiteralPath $Directory -Recurse -File -Filter 'Binary.Only.pas').Count -ne 0){throw 'Provider source exists in the consumer project'}
    if(@(Get-ChildItem -LiteralPath $Directory -Recurse -File -Filter 'Binary.Only.dcu').Count -ne 1){throw 'Provider was rebuilt or is missing'}
}
try{
    $source=Join-Path $producer 'Binary.Only.pas'
    Copy-Item -LiteralPath (Join-Path $fixture 'Binary.Only.source.txt') -Destination $source
    $arguments=@('-B',('-N0"'+$binary+'"'),('-U"'+(Join-Path $bds "lib/$Platform/release")+'"'),('"'+$source+'"'))
    Invoke-BinaryProcess $compiler $arguments 'provider-build' | Out-Null
    $dcu=Join-Path $binary 'Binary.Only.dcu'
    $evidence.dcuSha256=(Get-FileHash -LiteralPath $dcu).Hash
    Assert-BinaryInputs $working
    Invoke-BinaryCleaner $working 'preview' $true
    foreach($name in $hashes.Keys){if((Get-FileHash (Join-Path $working $name)).Hash -ne $hashes[$name]){throw "Dry-run changed $name"}}
    $program=Join-Path $working ".artifacts/$Platform/Debug/BinaryRuntime.exe"
    $before=Invoke-BinaryProcess $program @() 'before'
    if($before -ne 'BinaryInit|Main|BinaryFinal'){throw "Wrong initial behavior: $before"}
    Invoke-BinaryCleaner $working 'apply' $false
    $after=Invoke-BinaryProcess $program @() 'after'
    if($after -ne $before){throw "Binary effects changed: $after"}
    $consumer=Get-Content (Join-Path $working 'Binary.Consumer.pas') -Raw
    if(-not $consumer.Contains('Binary.Only') -or $consumer.Contains('Binary.Unused')){throw 'Wrong dependency edits'}
    $diagnostic=Get-Content (Join-Path $output 'apply.out') -Raw
    if($diagnostic -notmatch 'Binary\.Only.*unknown.*Source or exports could not be resolved'){throw 'Missing source-unavailable diagnostic'}
    $control=Join-Path $root 'control'
    Copy-Item -LiteralPath $working -Destination $control -Recurse
    $path=Join-Path $control 'Binary.Consumer.pas'
    $text=[IO.File]::ReadAllText($path)
    if(-not $text.Contains('uses Binary.Only;')){throw 'Negative control did not match preserved import'}
    [IO.File]::WriteAllText($path,$text.Replace('uses Binary.Only;',''),[Text.UTF8Encoding]::new($false))
    Invoke-BinaryCleaner $control 'control-build' $true
    $without=Invoke-BinaryProcess (Join-Path $control ".artifacts/$Platform/Debug/BinaryRuntime.exe") @() 'control-run'
    if($without -ne 'Main'){throw "Negative control retained binary effects: $without"}
    Assert-BinaryInputs $working
    Assert-BinaryInputs $control
    if((Get-FileHash -LiteralPath $dcu).Hash -ne $evidence.dcuSha256){throw 'Provider DCU changed'}
    foreach($name in $hashes.Keys){if((Get-FileHash (Join-Path $fixture $name)).Hash -ne $hashes[$name]){throw "Versioned fixture changed $name"}}
    $evidence.observations=@{before=$before; after=$after; withoutImport=$without}
    $evidence.contracts=@('package-dcu-only')
    $evidence.status='PASS'
    Write-Host "$Platform DCU-only runtime passed: $before before/after; control $without."
}
catch{$evidence.status='FAIL';$evidence.error=$_.Exception.Message;throw}
finally{
    $evidence.finishedUtc=[DateTime]::UtcNow.ToString('o')
    $evidence | ConvertTo-Json -Depth 8 | Set-Content $evidencePath -Encoding utf8NoBOM
}
