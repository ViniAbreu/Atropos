unit Atropos.Adapters.ProjectEvaluationScript;

interface

type
  TProjectEvaluationScript = class
  public
    class function Build(const ARequest: string): string; static;
  end;

implementation

uses System.SysUtils, System.NetEncoding;

class function TProjectEvaluationScript.Build(const ARequest: string): string;
begin
  Result := '$requestBase64 = ''' + TNetEncoding.Base64.Encode(ARequest) + '''' + sLineBreak +
    '$ErrorActionPreference = ''Stop''' + sLineBreak +
    '[void][Reflection.Assembly]::Load(''Microsoft.Build, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a'')' + sLineBreak +
    '$request = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($requestBase64)) | ConvertFrom-Json' + sLineBreak +
    '$collection = New-Object Microsoft.Build.Evaluation.ProjectCollection' + sLineBreak +
    'function Read-Hashes($project) {' + sLineBreak +
    ' $hashes = @{}' + sLineBreak +
    ' $paths = @($project.FullPath) + @($project.Imports | ForEach-Object { $_.ImportedProject.FullPath })' + sLineBreak +
    ' $algorithm = [Security.Cryptography.SHA256]::Create()' + sLineBreak +
    ' try { foreach ($path in $paths) { $hashes[$path] = [BitConverter]::ToString($algorithm.ComputeHash([IO.File]::ReadAllBytes($path))).Replace(''-'', '''') } } finally { $algorithm.Dispose() }' + sLineBreak +
    ' return $hashes' + sLineBreak +
    '}' + sLineBreak +
    'function Read-List([string]$value) { return @($value.Split('';'') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '''' }) }' + sLineBreak +
    'function Read-Paths([string]$value) {' + sLineBreak +
    ' return @(Read-List $value | ForEach-Object { [IO.Path]::GetFullPath([IO.Path]::Combine($basePath, $_)) })' + sLineBreak +
    '}' + sLineBreak +
    'try {' + sLineBreak +
    ' if ($request.configuration -ne '''') { $collection.SetGlobalProperty(''Config'', $request.configuration) }' + sLineBreak +
    ' if ($request.platform -ne '''') { $collection.SetGlobalProperty(''Platform'', $request.platform) }' + sLineBreak +
    ' $project = $collection.LoadProject($request.projectPath)' + sLineBreak +
    ' $before = Read-Hashes $project' + sLineBreak +
    ' $collection.UnloadAllProjects()' + sLineBreak +
    ' $project = $collection.LoadProject($request.projectPath)' + sLineBreak +
    ' $after = Read-Hashes $project' + sLineBreak +
    ' if ($before.Count -ne $after.Count) { throw ''Project import set changed during evaluation.'' }' + sLineBreak +
    ' foreach ($path in $before.Keys) { if ($before[$path] -ne $after[$path]) { throw (''Project input changed during evaluation: '' + $path) } }' + sLineBreak +
    ' $basePath = [IO.Path]::GetDirectoryName($project.FullPath)' + sLineBreak +
    ' $platform = $project.GetPropertyValue(''Platform'')' + sLineBreak +
    ' $compilerPath = ''''' + sLineBreak +
    ' if ($platform -eq ''Win32'') { $compilerPath = [IO.Path]::Combine($env:BDS, ''bin\dcc32.exe'') }' + sLineBreak +
    ' if ($platform -eq ''Win64'') { $compilerPath = [IO.Path]::Combine($env:BDS, ''bin\dcc64.exe'') }' + sLineBreak +
    ' $compilerVersion = ''''' + sLineBreak +
    ' if ($compilerPath -ne '''' -and [IO.File]::Exists($compilerPath)) { $compilerVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($compilerPath).FileVersion }' + sLineBreak +
    ' $search = $project.GetPropertyValue(''UnitSearchPath'')' + sLineBreak +
    ' if ($search -eq '''') { $search = $project.GetPropertyValue(''DCC_UnitSearchPath'') }' + sLineBreak +
    ' $include = $project.GetPropertyValue(''IncludePath'')' + sLineBreak +
    ' if ($include -eq '''') { $include = $search }' + sLineBreak +
    ' $options = @{}' + sLineBreak +
    ' foreach ($name in @(''RangeChecking'',''AssertionsAtRuntime'',''OverflowChecking'',''TypedAtParameter'',''ScopedEnums'',''ZeroBasedStrings'',''WritableConstants'',''CompleteBooleanEval'',''ConsoleTarget'',''DynamicPackages'',''UnitOutputDirectory'')) {' + sLineBreak +
    '  $options[$name] = $project.GetPropertyValue(''DCC_'' + $name)' + sLineBreak +
    ' }' + sLineBreak +
    ' $deferred = @($project.Targets.Values | ForEach-Object { $_.Children } | Where-Object { $_.GetType().Name -eq ''ProjectPropertyGroupTaskInstance'' } | ForEach-Object { $_.Properties } | Where-Object { $_.Name -match ''^(DCC_|UnitSearchPath$|IncludePath$|MainSource$)'' } | ForEach-Object { $_.Name } | Sort-Object -Unique)' + sLineBreak +
    ' $main = $project.GetPropertyValue(''MainSource'')' + sLineBreak +
    ' if ($main -ne '''') { $main = [IO.Path]::GetFullPath([IO.Path]::Combine($basePath, $main)) }' + sLineBreak +
    ' $result = [ordered]@{' + sLineBreak +
    '  projectPath = $project.FullPath' + sLineBreak +
    '  configuration = $project.GetPropertyValue(''Config'')' + sLineBreak +
    '  platform = $platform' + sLineBreak +
    '  mainSource = $main' + sLineBreak +
    '  compilerPath = $compilerPath' + sLineBreak +
    '  compilerFileVersion = $compilerVersion' + sLineBreak +
    '  defines = @(Read-List ($project.GetPropertyValue(''DCC_Define'')))' + sLineBreak +
    '  unitPaths = @($project.GetItems(''DCCReference'') | Where-Object { [IO.Path]::GetExtension($_.EvaluatedInclude) -eq ''.pas'' } | ForEach-Object { $_.GetMetadataValue(''FullPath'') })' + sLineBreak +
    '  searchPaths = @(Read-Paths $search)' + sLineBreak +
    '  includePaths = @(Read-Paths $include)' + sLineBreak +
    '  namespaces = @(Read-List ($project.GetPropertyValue(''DCC_Namespace'')))' + sLineBreak +
    '  aliases = @(Read-List ($project.GetPropertyValue(''DCC_UnitAlias'')))' + sLineBreak +
    '  options = $options' + sLineBreak +
    '  projectFiles = @($after.Keys | Sort-Object | ForEach-Object { @{ path = $_; sha256 = $after[$_] } })' + sLineBreak +
    '  deferredProperties = $deferred' + sLineBreak +
    ' }' + sLineBreak +
    ' $json = $result | ConvertTo-Json -Depth 8 -Compress' + sLineBreak +
    ' [Console]::WriteLine(''ATROPOS_CONTEXT='' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)))' + sLineBreak +
    '} finally { $collection.UnloadAllProjects(); $collection.Dispose() }';
end;

end.
