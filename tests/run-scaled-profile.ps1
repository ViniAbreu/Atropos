param(
    [ValidateSet('Win32','Win64')][string]$Platform='Win32',
    [string]$BdsVersion='23.0',
    [ValidateRange(1,10)][int]$Repetitions=3,
    [ValidateRange(8,2048)][int[]]$SymbolCounts=@(128,512)
)
$ErrorActionPreference='Stop'
$repository=Split-Path $PSScriptRoot -Parent
$output=Join-Path $repository ('artifacts/performance/scaled/'+$Platform+'/'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($output) | Out-Null
$bds="C:\Program Files (x86)\Embarcadero\Studio\$BdsVersion"
$msbuild="$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe"
$manifest=[ordered]@{status='RUNNING'; platform=$Platform; startedUtc=[DateTime]::UtcNow.ToString('o');
    runnerSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash; sourceHashes=@{}; measurements=@()}
foreach($file in Get-ChildItem (Join-Path $repository 'src') -Recurse -File | Where-Object Extension -in @('.pas','.inc')){
    $manifest.sourceHashes[$file.FullName.Substring($repository.Length+1)]=(Get-FileHash -LiteralPath $file.FullName).Hash
}
$manifestPath=Join-Path $output 'run.json'
function Save-Manifest{$manifest | ConvertTo-Json -Depth 10 | Set-Content $manifestPath -Encoding utf8NoBOM}
function Invoke-ProfileBuild([string]$Project,[string]$Config,[string]$Log){
    $command='"{0}\bin\rsvars.bat" && "{1}" "{2}" /t:Build /p:Config={3} /p:Platform={4} /p:DelphiLibraryPath="{0}\lib\{4}\release" /nologo /v:minimal' -f $bds,$msbuild,$Project,$Config,$Platform
    & cmd.exe /d /c $command *> $Log
    if($LASTEXITCODE -ne 0){throw "Build failed: $Log"}
}
function Read-Runtime([string]$Executable){
    $value=(& $Executable) -join '|'
    if($LASTEXITCODE -ne 0){throw "Runtime failed: $Executable"}
    return $value.Trim()
}
Save-Manifest
try{
    Invoke-ProfileBuild (Join-Path $PSScriptRoot 'AtroposProfile.dproj') Release (Join-Path $output 'harness-build.log')
    $harness=Join-Path $PSScriptRoot "profile-bin/$Platform/AtroposProfile.exe"
    $manifest.harnessSha256=(Get-FileHash $harness).Hash
    $manifest.harnessSourceSha256=(Get-FileHash (Join-Path $PSScriptRoot 'AtroposProfile.dpr')).Hash
    $manifest.delphiAstCommit=(& git -C (Join-Path $repository 'third_party/DelphiAST') rev-parse HEAD)
    foreach($symbols in $SymbolCounts){
        foreach($repeat in 1..$Repetitions){
            $working=Join-Path $output "symbols-$symbols-repeat-$repeat"
            & (Join-Path $PSScriptRoot 'New-ScaledProfileFixture.ps1') -OutputDirectory $working -SymbolsPerProvider $symbols
            $fixture=Get-Content (Join-Path $working 'fixture.json') -Raw | ConvertFrom-Json
            $project=Join-Path $working 'ScaledProfile.dproj'
            Invoke-ProfileBuild $project Debug (Join-Path $working 'baseline-build.log')
            $program=Join-Path $working ".artifacts/$Platform/Debug/ScaledProfile.exe"
            $before=Read-Runtime $program
            if($before -ne $fixture.expectedOutput){throw "Unexpected baseline: $before"}
            $resultPath=Join-Path $working 'profile.json'
            & $harness $project Debug $Platform $resultPath *> (Join-Path $working 'profile.log')
            if($LASTEXITCODE -ne 0){throw "Profile failed: $working"}
            $after=Read-Runtime $program
            if($after -ne $before){throw "Runtime changed: $after"}
            foreach($consumer in 1..$fixture.consumers){
                $content=Get-Content (Join-Path $working "Scale.Consumer$consumer.pas") -Raw
                if($content.Contains('Scale.Unused')){throw "Unused import was not removed: $consumer"}
                foreach($provider in 1..$fixture.providers){
                    if($content -notmatch ('\bScale\.Provider'+$provider+'\b')){throw "Required provider removed: $provider"}
                }
            }
            foreach($name in $fixture.sourceHashes.PSObject.Properties.Name | Where-Object {$_ -notlike 'Scale.Consumer*'}){
                if((Get-FileHash (Join-Path $working $name)).Hash -ne $fixture.sourceHashes.$name){throw "Unexpected source change: $name"}
            }
            $result=Get-Content $resultPath -Raw | ConvertFrom-Json
            if($result.status -ne 'PASS'){throw 'Profile status is not PASS.'}
            foreach($phase in @('execution','builds','project-evaluation','parsing','extraction','resolution','decisions','editing-plan','editing-write')){
                if($phase -notin $result.samples.phase){throw "Missing phase: $phase"}
            }
            $total=($result.samples | Where-Object phase -eq 'execution' | Measure-Object inclusiveMs -Sum).Sum
            $exclusive=($result.samples | Measure-Object exclusiveMs -Sum).Sum
            if([Math]::Abs($total-$exclusive) -gt 1){throw 'Phase accounting mismatch.'}
            $builds=($result.samples | Where-Object phase -eq 'builds' | Measure-Object calls -Sum).Sum
            if($builds -lt 2){throw 'Missing verification build.'}
            $phases=@{}
            foreach($group in $result.samples | Group-Object phase){
                $phases[$group.Name]=[ordered]@{calls=($group.Group | Measure-Object calls -Sum).Sum;
                    exclusiveMs=($group.Group | Measure-Object exclusiveMs -Sum).Sum;
                    inclusiveMs=($group.Group | Measure-Object inclusiveMs -Sum).Sum}
            }
            $manifest.measurements += [ordered]@{symbols=$symbols; repeat=$repeat; totalMs=$total;
                before=$before; after=$after; fixture=$fixture; phases=$phases;
                profilePath=$resultPath; profileSha256=(Get-FileHash $resultPath).Hash}
            Save-Manifest
            Write-Host "$Platform symbols=$symbols repeat=$repeat`: $([Math]::Round($total,2)) ms; runtime $after."
        }
    }
    foreach($name in $manifest.sourceHashes.Keys){
        if((Get-FileHash (Join-Path $repository $name)).Hash -ne $manifest.sourceHashes[$name]){throw "Source changed during measurement: $name"}
    }
    $manifest.status='PASS'
}
catch{$manifest.status='FAIL';$manifest.error=$_.Exception.Message;throw}
finally{$manifest.finishedUtc=[DateTime]::UtcNow.ToString('o');Save-Manifest;Write-Host "Evidence: $manifestPath"}
