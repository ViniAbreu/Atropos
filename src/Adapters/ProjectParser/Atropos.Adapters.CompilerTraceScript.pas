unit Atropos.Adapters.CompilerTraceScript;

interface

type
  TCompilerTraceScript = class
  public
    class function Build(const ARequest: string): string; static;
  end;

implementation

uses System.SysUtils, System.NetEncoding, Atropos.Adapters.CompilerContextSignature;

class function TCompilerTraceScript.Build(const ARequest: string): string;
begin
  Result := '$requestBase64 = ''' + TNetEncoding.Base64.Encode(ARequest) + '''' + sLineBreak +
    '$ErrorActionPreference = ''Stop''' + sLineBreak +
    '[void][Reflection.Assembly]::Load(''Microsoft.Build, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a'')' + sLineBreak +
    '$request = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($requestBase64)) | ConvertFrom-Json' + sLineBreak +
    '$collection = New-Object Microsoft.Build.Evaluation.ProjectCollection' + sLineBreak +
    TCompilerContextSignature.Script + sLineBreak +
    'function Assert-Inputs {' + sLineBreak +
    ' $algorithm = [Security.Cryptography.SHA256]::Create()' + sLineBreak +
    ' try {' + sLineBreak +
    '  foreach ($inputFile in $request.projectFiles) {' + sLineBreak +
    '   $actual = [BitConverter]::ToString($algorithm.ComputeHash([IO.File]::ReadAllBytes($inputFile.filePath))).Replace(''-'', '''')' + sLineBreak +
    '   if ($actual -ne $inputFile.contentHash) { throw (''Project input changed: '' + $inputFile.filePath) }' + sLineBreak +
    '  }' + sLineBreak +
    ' } finally { $algorithm.Dispose() }' + sLineBreak +
    '}' + sLineBreak +
    'try {' + sLineBreak +
    ' if (@($request.projectFiles).Count -eq 0) { throw ''Compiler preparation requires project input hashes.'' }' + sLineBreak +
    ' Assert-Inputs' + sLineBreak +
    ' $collection.SetGlobalProperty(''Config'', $request.configuration)' + sLineBreak +
    ' $collection.SetGlobalProperty(''Platform'', $request.platform)' + sLineBreak +
    ' $project = $collection.LoadProject($request.projectPath)' + sLineBreak +
    ' if ((Read-CompilerContextHash $project) -ne $request.compilerContextHash) { throw ''Compiler context changed since project evaluation.'' }' + sLineBreak +
    ' $knownInputs = @{}' + sLineBreak +
    ' foreach ($inputFile in $request.projectFiles) { $knownInputs[[IO.Path]::GetFullPath($inputFile.filePath)] = $true }' + sLineBreak +
    ' $loadedInputs = @($project.FullPath) + @($project.Imports | ForEach-Object { $_.ImportedProject.FullPath })' + sLineBreak +
    ' foreach ($loadedInput in $loadedInputs) {' + sLineBreak +
    '  if (-not $knownInputs.ContainsKey([IO.Path]::GetFullPath($loadedInput))) { throw (''New project import during compiler preparation: '' + $loadedInput) }' + sLineBreak +
    ' }' + sLineBreak +
    ' $instance = $project.CreateProjectInstance()' + sLineBreak +
    ' if ($instance.InitialTargets.Count -ne 0) { throw ''Compiler preparation cannot execute project initial targets.'' }' + sLineBreak +
    ' $targets = @(''__RemoveLatestBackSlashFromPaths'', ''__GenerateSearchPathFile'', ''__GenerateObjPathFile'', ''__GenerateResourcePathFile'', ''__GenerateUnitSearchPathFile'', ''_PasCoreCompile'')' + sLineBreak +
    ' $compilerTargets = [IO.Path]::GetFullPath([IO.Path]::Combine($env:BDS, ''bin\CodeGear.Delphi.Targets''))' + sLineBreak +
    ' foreach ($targetName in $targets) {' + sLineBreak +
    '  if (-not $instance.Targets.ContainsKey($targetName)) { throw (''Required compiler target not found: '' + $targetName) }' + sLineBreak +
    '  if ([IO.Path]::GetFullPath($instance.Targets[$targetName].Location.File) -ne $compilerTargets) { throw (''Compiler target was replaced: '' + $targetName) }' + sLineBreak +
    ' }' + sLineBreak +
    ' foreach ($targetRoot in (@($project.Xml) + @($project.Imports | ForEach-Object { $_.ImportedProject }))) {' + sLineBreak +
    '  foreach ($target in $targetRoot.Targets) {' + sLineBreak +
    '   foreach ($hook in ($project.ExpandString($target.BeforeTargets + '';'' + $target.AfterTargets).Split('';''))) {' + sLineBreak +
    '    if ($targets -contains $hook.Trim()) { throw (''Compiler target has a project hook: '' + $target.Name) }' + sLineBreak +
    '   }' + sLineBreak +
    '  }' + sLineBreak +
    ' }' + sLineBreak +
    ' foreach ($property in @(''DCC_ExeOutput'',''DCC_DcuOutput'',''DCC_BplOutput'',''DCC_DcpOutput'',''DCC_HppOutput'',''DCC_ObjOutput'',''DCC_BpiOutput'',''DCC_ResourceOutput'')) {' + sLineBreak +
    '  [void]$instance.SetProperty($property, $request.outputPath)' + sLineBreak +
    ' }' + sLineBreak +
    ' if ($request.sourceDirectory) {' + sLineBreak +
    '  [void]$instance.SetProperty(''UnitSearchPath'', $instance.GetPropertyValue(''UnitSearchPath'') + '';'' + $request.sourceDirectory)' + sLineBreak +
    ' }' + sLineBreak +
    ' [void]$instance.SetProperty(''DCC_ForceExecute'', ''true'')' + sLineBreak +
    ' if ($request.collectDependencies) {' + sLineBreak +
    '  [void]$instance.SetProperty(''DCC_OutputDependencies'', ''true'')' + sLineBreak +
    '  [void]$instance.SetProperty(''DCC_MakeModifiedUnits'', ''true'')' + sLineBreak +
    ' }' + sLineBreak +
    ' [void]$instance.SetProperty(''CmdsFileOutput'', [IO.Path]::Combine($request.outputPath, ''AtroposTrace.cmds''))' + sLineBreak +
    ' [void]$instance.SetProperty(''_GenerateCmdsFile'', ($targets[0..4] -join '';''))' + sLineBreak +
    ' [void]$instance.AddItem(''_ProjectFiles'', $request.sourcePath)' + sLineBreak +
    ' [void]$instance.SetProperty(''_ProjectFiles'', $request.sourcePath)' + sLineBreak +
    ' $logger = New-Object Microsoft.Build.Logging.ConsoleLogger' + sLineBreak +
    ' $logger.Verbosity = [Microsoft.Build.Framework.LoggerVerbosity]::Normal' + sLineBreak +
    ' $logger.Parameters = ''NoSummary''' + sLineBreak +
    ' Assert-Inputs' + sLineBreak +
    ' $succeeded = $instance.Build([string[]]@(''_PasCoreCompile''), [Microsoft.Build.Framework.ILogger[]]@($logger))' + sLineBreak +
    ' if (-not $succeeded) { throw ''Compiler branch preparation failed.'' }' + sLineBreak +
    ' Assert-Inputs' + sLineBreak +
    ' if ((Read-CompilerContextHash $project) -ne $request.compilerContextHash) { throw ''Compiler context changed during compilation.'' }' + sLineBreak +
    ' if (-not [IO.File]::Exists([IO.Path]::Combine($request.outputPath, $request.artifactName))) { throw ''Compiler preparation produced no artifact.'' }' + sLineBreak +
    '} finally { $collection.UnloadAllProjects(); $collection.Dispose() }';
end;

end.
