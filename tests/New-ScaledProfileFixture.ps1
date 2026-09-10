param(
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [ValidateRange(2,64)][int]$Providers=16,
    [ValidateRange(2,128)][int]$Consumers=32,
    [ValidateRange(8,2048)][int]$SymbolsPerProvider=128
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputDirectory){throw 'Fixture output must be a new directory.'}
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$encoding=[Text.UTF8Encoding]::new($false)
function Write-Source([string]$Name,[string]$Source){
    [IO.File]::WriteAllText((Join-Path $OutputDirectory $Name),$Source.Replace("`r`n","`n"),$encoding)
}
$providerNames=@(1..$Providers | ForEach-Object { 'Scale.Provider'+$_ })
foreach($provider in 1..$Providers){
    $constants=@(1..$SymbolsPerProvider | ForEach-Object { '  Value{0}_{1} = {2};' -f $provider,$_,($provider*10000+$_) })
    Write-Source ($providerNames[$provider-1]+'.pas') ("unit $($providerNames[$provider-1]);`ninterface`nconst`n"+($constants -join "`n")+"`nimplementation`nend.`n")
}
Write-Source 'Scale.Unused.pas' "unit Scale.Unused;`ninterface`nconst NeverUsed = 0;`nimplementation`nend.`n"
$consumerNames=@(1..$Consumers | ForEach-Object { 'Scale.Consumer'+$_ })
$expected=[long]0
foreach($consumer in 1..$Consumers){
    $terms=@()
    foreach($provider in 1..$Providers){
        foreach($offset in 0..3){
            $symbol=$SymbolsPerProvider-$offset
            $terms+='Value{0}_{1}' -f $provider,$symbol
            $expected+=$provider*10000+$symbol
        }
    }
    $uses=($providerNames+@('Scale.Unused')) -join ', '
    Write-Source ($consumerNames[$consumer-1]+'.pas') ("unit $($consumerNames[$consumer-1]);`ninterface`nuses $uses;`nfunction Compute$consumer`: Int64;`nimplementation`nfunction Compute$consumer`: Int64;`nbegin`n  Result := "+($terms -join " +`n    ")+";`nend;`nend.`n")
}
$calls=@(1..$Consumers | ForEach-Object { 'Compute'+$_ })
Write-Source 'ScaledProfile.dpr' ('program ScaledProfile;' + "`n" + '{$APPTYPE CONSOLE}' + "`nuses System.SysUtils, "+($consumerNames -join ', ')+";`nbegin`n  Writeln("+($calls -join ' + ')+");`nend.`n")
$references=@($providerNames+$consumerNames+@('Scale.Unused') | ForEach-Object { '    <DCCReference Include="'+$_+'.pas" />' })
$project=@'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <MainSource>ScaledProfile.dpr</MainSource><Base>true</Base>
    <Config Condition="'$(Config)'==''">Debug</Config>
    <Platform Condition="'$(Platform)'==''">Win32</Platform>
    <AppType>Console</AppType><FrameworkType>None</FrameworkType>
    <ProjectVersion>20.1</ProjectVersion><DCC_ConsoleTarget>true</DCC_ConsoleTarget>
    <DCC_Namespace>System</DCC_Namespace>
    <DCC_DcuOutput>.artifacts\$(Platform)\$(Config)</DCC_DcuOutput>
    <DCC_ExeOutput>.artifacts\$(Platform)\$(Config)</DCC_ExeOutput>
  </PropertyGroup>
  <ItemGroup>
    <DelphiCompile Include="ScaledProfile.dpr"><MainSource>MainSource</MainSource></DelphiCompile>
    <BuildConfiguration Include="Debug"><Key>Debug</Key></BuildConfiguration>
REFERENCES
  </ItemGroup>
  <Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets" />
</Project>
'@
Write-Source 'ScaledProfile.dproj' $project.Replace('REFERENCES',($references -join "`n"))
$hashes=@{}
foreach($file in Get-ChildItem -LiteralPath $OutputDirectory -File){$hashes[$file.Name]=(Get-FileHash -LiteralPath $file.FullName).Hash}
[ordered]@{providers=$Providers; consumers=$Consumers; symbolsPerProvider=$SymbolsPerProvider;
    referencesPerConsumer=4*$Providers; expectedOutput=$expected.ToString(); sourceHashes=$hashes;
    generatorSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash} |
    ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutputDirectory 'fixture.json') -Encoding utf8NoBOM
