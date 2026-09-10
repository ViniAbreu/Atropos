unit Probe.Engine;

interface

uses System.JSON, System.SysUtils, Atropos.Core.Ports, Atropos.Core.Domain;

type
  TProbeEngine = class
  private
    FParser: IASTParser;
    FResolver: IExternalUnitResolver;
    FObservation: TJSONObject;
    FRequest: TJSONObject;
    FStage: string;
    procedure RegisterDependency(Context: TProjectContext; Dependency: TJSONObject);
    procedure RegisterDependencies(Context: TProjectContext);
    procedure ObserveTree(const Tree: IUnitSyntaxTree);
    procedure Analyze(const Tree: IUnitSyntaxTree; Context: TProjectContext);
    procedure Rewrite(const Analysis: TUnitAnalysisResult);
    procedure RunAnalysis;
    function CreateContext: TProjectContext;
  public
    constructor Create;
    function Execute(Request: TJSONObject): TJSONObject;
  end;

implementation

uses System.Classes, System.IOUtils, System.Diagnostics,
  Atropos.Adapters.DelphiAST, Atropos.Adapters.ExternalUnitResolver,
  Atropos.Core.Config, Atropos.Core.Modifier, Probe.Json, Probe.MemoryFile;

constructor TProbeEngine.Create;
begin
  inherited Create;
  FParser := TDelphiASTAdapter.Create;
end;

procedure TProbeEngine.RegisterDependency(Context: TProjectContext; Dependency: TJSONObject);
var Tree: IUnitSyntaxTree; Data: TJSONObject; All: TJSONArray;
begin
  FStage := 'dependency';
  Tree := FParser.ParseFile(TProbeJson.Text(Dependency, 'path'));
  Context.RegisterUnitExports(Tree.GetUnitName, Tree.GetExportedIdentifiers,
    Tree.HasInitializationSection, TProbeJson.Flag(Dependency, 'native'));
  Data := TJSONObject.Create;
  Data.AddPair('unit', Tree.GetUnitName);
  TProbeJson.Put(Data, 'exports', Tree.GetExportedIdentifiers);
  Data.AddPair('initialization', TJSONBool.Create(Tree.HasInitializationSection));
  All := FObservation.GetValue('dependencies') as TJSONArray;
  All.AddElement(Data);
end;

procedure TProbeEngine.RegisterDependencies(Context: TProjectContext);
var Items: TJSONArray; Item: TJSONValue;
begin
  Items := FRequest.GetValue('dependencies') as TJSONArray;
  if not Assigned(Items) then
    Exit;
  for Item in Items do
    RegisterDependency(Context, Item as TJSONObject);
end;

function TProbeEngine.CreateContext: TProjectContext;
begin
  if not TProbeJson.Flag(FRequest, 'resolver') then
    Exit(TProjectContext.Create);
  FResolver := TExternalUnitResolverAdapter.Create(FParser);
  FResolver.Initialize(TProbeJson.Strings(FRequest, 'searchPaths'), '',
    TPath.GetDirectoryName(TProbeJson.Text(FRequest, 'consumer')));
  Result := TProjectContext.Create(FResolver);
end;

procedure TProbeEngine.ObserveTree(const Tree: IUnitSyntaxTree);
begin
  FStage := 'extract';
  FObservation.AddPair('unit', Tree.GetUnitName);
  TProbeJson.Put(FObservation, 'interfaceUses', Tree.GetInterfaceUses);
  TProbeJson.Put(FObservation, 'implementationUses', Tree.GetImplementationUses);
  TProbeJson.Put(FObservation, 'interfaceIdentifiers', Tree.GetIdentifiersUsedInInterface);
  TProbeJson.Put(FObservation, 'implementationIdentifiers', Tree.GetIdentifiersUsedInImplementation);
  TProbeJson.Put(FObservation, 'exports', Tree.GetExportedIdentifiers);
  FObservation.AddPair('initialization', TJSONBool.Create(Tree.HasInitializationSection));
end;

procedure TProbeEngine.Analyze(const Tree: IUnitSyntaxTree; Context: TProjectContext);
var Analyzer: TAnalyzeUnitUses; Analysis: TUnitAnalysisResult;
begin
  FStage := 'analyze';
  Analyzer := TAnalyzeUnitUses.Create;
  try
    Analysis := Analyzer.Execute(Tree, Context);
    TProbeJson.Put(FObservation, 'unused', Analysis.UnusedUnits);
    TProbeJson.Put(FObservation, 'moved', Analysis.UnitsToMoveToImpl);
    TProbeJson.Put(FObservation, 'ambiguities', Analysis.PreservedAmbiguities);
    TProbeJson.Put(FObservation, 'preservationReasons', Analysis.PreservationReasons);
    Rewrite(Analysis);
  finally
    Analyzer.Free;
  end;
end;

procedure TProbeEngine.Rewrite(const Analysis: TUnitAnalysisResult);
var Files: IFileService; Modifier: TApplyUsesChanges; Config: TToolConfig;
  Changes: TUnitAnalysisResult; Override: TJSONObject;
  Original, Modified, FilePath: string;
begin
  if not TProbeJson.Flag(FRequest, 'rewrite') then
    Exit;
  FStage := 'rewrite';
  FilePath := TProbeJson.Text(FRequest, 'consumer');
  Original := TFile.ReadAllText(FilePath);
  Files := TProbeMemoryFile.Create(Original);
  Config := TToolConfig.Default;
  Config.RemoveUnused := TProbeJson.Flag(FRequest, 'removeEnabled', True);
  Config.MoveToImplementation := TProbeJson.Flag(FRequest, 'moveEnabled', True);
  Changes := Analysis;
  Override := FRequest.GetValue('changes') as TJSONObject;
  if Assigned(Override) then
  begin
    Changes.UnusedUnits := TProbeJson.Strings(Override, 'unused');
    Changes.UnitsToMoveToImpl := TProbeJson.Strings(Override, 'moved');
  end;
  Modifier := TApplyUsesChanges.Create(Files, Config);
  try
    Modifier.Execute(FilePath, Changes);
    Modified := Files.ReadFileContent(FilePath);
    FObservation.AddPair('modified', Modified);
    Modifier.Execute(FilePath, Changes);
    FObservation.AddPair('idempotent', TJSONBool.Create(Modified = Files.ReadFileContent(FilePath)));
    FObservation.AddPair('unchanged', TJSONBool.Create(Original = Modified));
  finally
    Modifier.Free;
  end;
end;

procedure TProbeEngine.RunAnalysis;
var Context: TProjectContext; Tree: IUnitSyntaxTree; Timer: TStopwatch;
begin
  Context := CreateContext;
  try
    RegisterDependencies(Context);
    FStage := 'parse';
    Timer := TStopwatch.StartNew;
    Tree := FParser.ParseFile(TProbeJson.Text(FRequest, 'consumer'));
    FObservation.AddPair('parseMs', TJSONNumber.Create(Timer.Elapsed.TotalMilliseconds));
    Timer := TStopwatch.StartNew;
    ObserveTree(Tree);
    FObservation.AddPair('extractMs', TJSONNumber.Create(Timer.Elapsed.TotalMilliseconds));
    Timer := TStopwatch.StartNew;
    Analyze(Tree, Context);
    if Assigned(FResolver) then
      TProbeJson.Put(FObservation, 'resolverWarnings', FResolver.GetWarnings);
    FObservation.AddPair('analysisAndRewriteMs', TJSONNumber.Create(Timer.Elapsed.TotalMilliseconds));
  finally
    Context.Free;
  end;
end;

function TProbeEngine.Execute(Request: TJSONObject): TJSONObject;
var Timer: TStopwatch;
begin
  FRequest := Request;
  FObservation := TJSONObject.Create;
  FObservation.AddPair('protocol', TJSONNumber.Create(2));
  FObservation.AddPair('dependencies', TJSONArray.Create);
  Timer := TStopwatch.StartNew;
  try
    RunAnalysis;
    FObservation.AddPair('totalMs', TJSONNumber.Create(Timer.Elapsed.TotalMilliseconds));
    FObservation.AddPair('status', 'ok');
  except
    on Failure: Exception do
    begin
      FObservation.AddPair('status', 'error');
      FObservation.AddPair('errorStage', FStage);
      FObservation.AddPair('error', Failure.ClassName + ': ' + Failure.Message);
    end;
  end;
  Result := FObservation;
end;

end.
