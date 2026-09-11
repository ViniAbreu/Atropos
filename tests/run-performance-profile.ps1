param(
    [string]$BdsVersion = '23.0',
    [ValidateSet('Win32', 'Win64')][string]$Platform = 'Win32',
    [ValidateRange(1, 20)][int]$Repetitions = 3
)
$ErrorActionPreference = 'Stop'
$repository = Split-Path $PSScriptRoot -Parent
$output = Join-Path $repository "artifacts/performance/$Platform"
[IO.Directory]::CreateDirectory($output) | Out-Null
$manifestPath = Join-Path $output 'run.json'
$inputs = @{}
foreach ($file in Get-ChildItem (Join-Path $repository 'src') -Recurse -File | Where-Object Extension -in @('.pas','.inc')) {
    $inputs[$file.FullName.Substring($repository.Length + 1)] = (Get-FileHash -LiteralPath $file.FullName).Hash
}
$manifest = [ordered]@{status='RUNNING'; startedUtc=[DateTime]::UtcNow.ToString('o');
    platform=$Platform; repetitions=$Repetitions; sourceHashes=$inputs; measurements=@();
    runnerSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;
    harnessSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'AtroposProfile.dpr')).Hash;
    projectSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'AtroposProfile.dproj')).Hash;
    delphiAstCommit=(& git -C (Join-Path $repository 'third_party/DelphiAST') rev-parse HEAD)}
$manifest | ConvertTo-Json -Depth 8 | Set-Content $manifestPath -Encoding utf8NoBOM
$rsvars = "C:\Program Files (x86)\Embarcadero\Studio\$BdsVersion\bin\rsvars.bat"
$msbuild = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe"
$libraryPath = "C:\Program Files (x86)\Embarcadero\Studio\$BdsVersion\lib\$Platform\release"
$project = Join-Path $PSScriptRoot 'AtroposProfile.dproj'
$command = '"{0}" && "{1}" "{2}" /t:Build /p:Config=Release /p:Platform={3} /p:DelphiLibraryPath="{4}" /nologo /v:minimal' -f $rsvars, $msbuild, $project, $Platform, $libraryPath
try {
    & cmd.exe /d /c $command *> (Join-Path $output 'build.log')
    if ($LASTEXITCODE -ne 0) { throw "Profiler build failed; see $output/build.log" }
    $executable = Join-Path $PSScriptRoot "profile-bin/$Platform/AtroposProfile.exe"
    $manifest.executableSha256 = (Get-FileHash $executable).Hash
    foreach ($fixtureName in @('RepresentativeConsole', 'LifecycleConsole', 'SemanticRuntime')) {
        $fixture = Join-Path $PSScriptRoot "Fixtures/$fixtureName"
        $fixtureHashes = @{}
        foreach ($file in Get-ChildItem -LiteralPath $fixture -File) {
            $fixtureHashes[$file.Name] = (Get-FileHash -LiteralPath $file.FullName).Hash
        }
        foreach ($repeat in 1..$Repetitions) {
            $temporary = Join-Path ([IO.Path]::GetTempPath()) ('AtroposProfile-' + [Guid]::NewGuid().ToString('N'))
            try {
                [IO.Directory]::CreateDirectory($temporary) | Out-Null
                Copy-Item -LiteralPath $fixture -Destination $temporary -Recurse
                $working = Join-Path $temporary $fixtureName
                $resultPath = Join-Path $output "$fixtureName-$repeat.json"
                & $executable (Join-Path $working "$fixtureName.dproj") Debug $Platform $resultPath
                if ($LASTEXITCODE -ne 0) { throw "Profile failed: $resultPath" }
                $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
                if ($result.status -ne 'PASS') { throw "Incomplete profile: $resultPath" }
                $phases = @($result.samples.phase | Sort-Object -Unique)
                foreach ($required in @('execution','builds','project-evaluation','target-preparation','parsing','extraction','resolution','decisions','editing-plan','editing-write')) {
                    if ($required -notin $phases) { throw "Missing phase $required in $resultPath" }
                }
                $total = ($result.samples | Where-Object phase -eq 'execution' | Measure-Object inclusiveMs -Sum).Sum
                $exclusive = ($result.samples | Measure-Object exclusiveMs -Sum).Sum
                if ([Math]::Abs($total - $exclusive) -gt 1.0) { throw 'Exclusive phase times do not account for execution time.' }
                $buildCalls = ($result.samples | Where-Object phase -eq 'builds' | Measure-Object calls -Sum).Sum
                if ($buildCalls -lt 2) { throw 'Profile did not exercise baseline and final builds.' }
                $changed = @($fixtureHashes.Keys | Where-Object { (Get-FileHash -LiteralPath (Join-Path $working $_)).Hash -ne $fixtureHashes[$_] })
                if ($changed.Count -eq 0) { throw 'Profile did not apply actual source edits.' }
                $manifest.measurements += [ordered]@{fixture=$fixtureName; repeat=$repeat; resultFile=$resultPath;
                    resultSha256=(Get-FileHash $resultPath).Hash; fixtureHashes=$fixtureHashes; changedFiles=$changed}
                Write-Host "$Platform $fixtureName #$repeat`: $([Math]::Round($total, 2)) ms."
            }
            finally {
                $resolved = [IO.Path]::GetFullPath($temporary)
                if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -or
                    -not (Split-Path $resolved -Leaf).StartsWith('AtroposProfile-')) { throw 'Unsafe profiler cleanup path.' }
                Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        foreach ($name in $fixtureHashes.Keys) {
            if ((Get-FileHash -LiteralPath (Join-Path $fixture $name)).Hash -ne $fixtureHashes[$name]) { throw "Versioned fixture changed: $name" }
        }
    }
    foreach ($name in $inputs.Keys) {
        if ((Get-FileHash -LiteralPath (Join-Path $repository $name)).Hash -ne $inputs[$name]) { throw "Source changed during profile: $name" }
    }
    $manifest.status = 'PASS'
}
catch {
    $manifest.status = 'FAIL'
    $manifest.error = $_.Exception.Message
    throw
}
finally {
    $manifest.finishedUtc = [DateTime]::UtcNow.ToString('o')
    $manifest | ConvertTo-Json -Depth 8 | Set-Content $manifestPath -Encoding utf8NoBOM
}
