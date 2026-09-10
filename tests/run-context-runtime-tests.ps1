param(
    [Parameter(Mandatory=$true)][string]$CliPath,
    [Parameter(Mandatory=$true)][ValidateSet('Win32','Win64')][string]$Platform
)
$ErrorActionPreference='Stop'
$cli=(Resolve-Path -LiteralPath $CliPath).Path
$fixture=Join-Path $PSScriptRoot 'Fixtures/ContextRuntime'
$output=Join-Path (Split-Path $PSScriptRoot -Parent) "artifacts/integration/$Platform/context-runtime"
$root=Join-Path $output ('work/'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($output) | Out-Null
$evidencePath=Join-Path $output 'result.json'
$hashes=@{}
foreach($file in Get-ChildItem -LiteralPath $fixture -Recurse -File){
    $hashes[$file.FullName.Substring($fixture.Length+1)]=(Get-FileHash -LiteralPath $file.FullName).Hash
}
$evidence=[ordered]@{status='RUNNING'; hostPlatform=$Platform; startedUtc=[DateTime]::UtcNow.ToString('o');
    runnerSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash; cliSha256=(Get-FileHash -LiteralPath $cli).Hash;
    catalogSha256=(Get-FileHash (Join-Path $PSScriptRoot 'SemanticProbe/scenarios/catalog.json')).Hash;
    fixtureHashes=$hashes; workingDirectory=$root; observations=@{}; contracts=@()}
$evidence | ConvertTo-Json -Depth 8 | Set-Content $evidencePath -Encoding utf8NoBOM
function Invoke-ContextProcess([string]$Executable,[string[]]$Arguments,[string]$Label){
    $stdout=Join-Path $output "$Label.out"; $stderr=Join-Path $output "$Label.err"
    $options=@{FilePath=$Executable; PassThru=$true; WindowStyle='Hidden'; RedirectStandardOutput=$stdout; RedirectStandardError=$stderr}
    if($Arguments.Count -gt 0){$options.ArgumentList=$Arguments}
    $process=Start-Process @options
    if(-not $process.WaitForExit(240000)){Stop-Process -Id $process.Id -Force; throw "$Label timed out"}
    $process.WaitForExit()
    $text=((Get-Content $stdout) -join '|').Trim()
    if($process.ExitCode -ne 0){throw "$Label failed: $text $(Get-Content $stderr -Raw)"}
    return $text
}
function Copy-ContextFixture([string]$Name){
    $directory=Join-Path $root $Name
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    Copy-Item -LiteralPath $fixture -Destination $directory -Recurse
    return (Join-Path $directory 'ContextRuntime')
}
function Invoke-ContextCleaner([string]$Working,[string]$Label,[bool]$DryRun,[bool]$Matrix){
    $arguments=@('-dproj',('"'+(Join-Path $Working 'ContextRuntime.dproj')+'"'),'--remove','--move')
    $targets=@("Debug|$Platform")
    if($Matrix){$targets=@('Debug|Win32','Release|Win32','Debug|Win64','Release|Win64')}
    foreach($target in $targets){$arguments+=@('--target',$target)}
    if($DryRun){$arguments+='--dry-run'}
    Invoke-ContextProcess $cli $arguments $Label | Out-Null
}
function Read-ContextMatrix([string]$Working,[string]$Label){
    $values=@{}
    foreach($target in @('Win32','Win64')){
        foreach($config in @('Debug','Release')){
            $key="$config|$target"
            $values[$key]=Invoke-ContextProcess (Join-Path $Working ".artifacts/$target/$config/ContextRuntime.exe") @() "$Label-$config-$target"
            $expected="${config}Alias|FirstNamespace|ChosenMapping|$target|${config}Define"
            if($values[$key] -ne $expected){throw "Wrong $key runtime: $($values[$key])"}
        }
    }
    return $values
}
try{
    $working=Copy-ContextFixture 'positive'
    Invoke-ContextCleaner $working 'preview' $true $true
    foreach($name in $hashes.Keys){if((Get-FileHash (Join-Path $working $name)).Hash -ne $hashes[$name]){throw "Dry-run changed $name"}}
    $evidence.observations.before=Read-ContextMatrix $working 'before'
    Invoke-ContextCleaner $working 'apply' $false $true
    $evidence.observations.after=Read-ContextMatrix $working 'after'
    $consumer=Get-Content (Join-Path $working 'Context.Consumer.pas') -Raw
    if($consumer.Contains('Context.Unused')){throw 'Unused import was not removed'}
    foreach($name in @('OldDep','NamespaceProvider','Mapped','Context.Platform32','Context.Platform64','Context.DebugOnly','Context.ReleaseOnly')){
        if(-not $consumer.Contains($name)){throw "Required import removed: $name"}
    }
    foreach($control in @('alias','namespace','mapping')){
        $copy=Copy-ContextFixture $control
        $path=Join-Path $copy 'context.props'
        $old='OldDep=Context.DebugAlias'; $new='OldDep=Context.ReleaseAlias'
        $expected="ReleaseAlias|FirstNamespace|ChosenMapping|$Platform|DebugDefine"
        if($control -eq 'namespace'){
            $old='First;Second;System'; $new='Second;First;System'
            $expected="DebugAlias|SecondNamespace|ChosenMapping|$Platform|DebugDefine"
        }
        if($control -eq 'mapping'){
            $path=Join-Path $copy 'ContextRuntime.dpr'; $old="chosen\Mapped.pas"; $new='Mapped.pas'
            $expected="DebugAlias|FirstNamespace|WrongMapping|$Platform|DebugDefine"
        }
        $source=[IO.File]::ReadAllText($path)
        if(-not $source.Contains($old)){throw "Control $control did not match"}
        [IO.File]::WriteAllText($path,$source.Replace($old,$new),[Text.UTF8Encoding]::new($false))
        Invoke-ContextCleaner $copy "$control-build" $true $false
        $value=Invoke-ContextProcess (Join-Path $copy ".artifacts/$Platform/Debug/ContextRuntime.exe") @() "$control-run"
        if($value -ne $expected){throw "Control $control returned $value"}
        $evidence.observations[$control]=$value
    }
    foreach($name in $hashes.Keys){if((Get-FileHash (Join-Path $fixture $name)).Hash -ne $hashes[$name]){throw "Versioned fixture changed $name"}}
    $evidence.contracts=@('project-define-debug-release','platform-win32-win64','namespace-prefix-resolution','unit-alias-resolution','project-in-path','project-imported-props')
    $evidence.status='PASS'
    Write-Host "$Platform context runtime passed for all four targets and three negative controls."
}
catch{$evidence.status='FAIL'; $evidence.error=$_.Exception.Message; throw}
finally{
    $evidence.finishedUtc=[DateTime]::UtcNow.ToString('o')
    $evidence | ConvertTo-Json -Depth 8 | Set-Content $evidencePath -Encoding utf8NoBOM
}
