unit Atropos.Tests.AnalysisSnapshot;

interface

uses DUnitX.TestFramework, Atropos.Core.Ports,
  Atropos.Tests.BuildReliability;

type
  TPlanningParserSpy = class(TInterfacedObject, IASTParser, IAnalysisSnapshot)
  public
    Files: TFileServiceSpy;
    ParseCount, WritesDuringParsing, ValidationCount: Integer;
    RejectValidation: Boolean;
    procedure BeginAnalysis;
    procedure ValidateAnalysis;
    function ParseFile(const AFilePath: string): IUnitSyntaxTree;
  end;

  [TestFixture]
  TAnalysisSnapshotTests = class
  private
    FRoot: string;
    FParser: IASTParser;
    FSnapshot: IAnalysisSnapshot;
    function WriteSource(const AName, AText: string): string;
    procedure RunPlanning(const AReject, ACancel, ADryRun: Boolean);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure UnchangedSourcesValidate;
    [Test] [TestCase('Root', 'Consumer.pas')]
    [TestCase('Include', 'body.inc')]
    procedure ChangedSourceInvalidatesPlan(const AName: string);
    [Test] procedure DeletedSourceInvalidatesPlan;
    [Test] procedure DifferentReadCannotBeHiddenByRestoringContent;
    [Test] procedure NewAnalysisResetsPriorSnapshot;
    [Test] procedure ResolvedProviderChangeInvalidatesSnapshot;
    [Test] procedure EveryUnitIsAnalyzedBeforeFirstWrite;
    [Test] procedure ValidationFailurePreventsAllWrites;
    [Test] procedure CancellationAfterAnalysisPreventsAllWrites;
    [Test] procedure DryRunConsumesTheSameValidatedPlan;
    [Test] procedure RealDependencyIncludeChangeAbortsBeforeEditing;
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils, Atropos.Adapters.DelphiAST,
  Atropos.Adapters.ExternalUnitResolver, Atropos.Application.AppService,
  Atropos.Adapters.FileSystem, Atropos.Core.Config;

procedure TPlanningParserSpy.BeginAnalysis;
begin
  ParseCount := 0;
end;

procedure TPlanningParserSpy.ValidateAnalysis;
begin
  Inc(ValidationCount);
  if RejectValidation then
    raise EInvalidOperation.Create('Source changed before applying analysis');
end;

function TPlanningParserSpy.ParseFile(const AFilePath: string): IUnitSyntaxTree;
begin
  Inc(ParseCount);
  Inc(WritesDuringParsing, Files.WriteCallCount);
  Result := TUnitSyntaxTreeStub.Create;
end;

procedure TAnalysisSnapshotTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'Atropos-Snapshot-' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
  FParser := TDelphiASTAdapter.Create;
  Assert.IsTrue(Supports(FParser, IAnalysisSnapshot, FSnapshot));
  FSnapshot.BeginAnalysis;
  WriteSource('body.inc', 'type TIncluded = Integer;');
  WriteSource('Consumer.pas', 'unit Consumer; interface {$I body.inc} implementation end.');
end;

procedure TAnalysisSnapshotTests.TearDown;
begin
  FSnapshot := nil;
  FParser := nil;
  if not TPath.GetFullPath(FRoot).StartsWith(
    TPath.Combine(TPath.GetTempPath, 'Atropos-Snapshot-'), True) then
    raise Exception.Create('Refusing cleanup outside snapshot test directory');
  TDirectory.Delete(FRoot, True);
end;

function TAnalysisSnapshotTests.WriteSource(const AName, AText: string): string;
begin
  Result := TPath.Combine(FRoot, AName);
  TFile.WriteAllText(Result, AText, TEncoding.UTF8);
end;

procedure TAnalysisSnapshotTests.UnchangedSourcesValidate;
begin
  FParser.ParseFile(TPath.Combine(FRoot, 'Consumer.pas'));
  FSnapshot.ValidateAnalysis;
end;

procedure TAnalysisSnapshotTests.ChangedSourceInvalidatesPlan(const AName: string);
begin
  FParser.ParseFile(TPath.Combine(FRoot, 'Consumer.pas'));
  WriteSource(AName, 'changed');
  Assert.WillRaise(procedure begin FSnapshot.ValidateAnalysis end, EInvalidOperation);
end;

procedure TAnalysisSnapshotTests.DeletedSourceInvalidatesPlan;
begin
  FParser.ParseFile(TPath.Combine(FRoot, 'Consumer.pas'));
  TFile.Delete(TPath.Combine(FRoot, 'body.inc'));
  Assert.WillRaise(procedure begin FSnapshot.ValidateAnalysis end, EInvalidOperation);
end;

procedure TAnalysisSnapshotTests.DifferentReadCannotBeHiddenByRestoringContent;
begin
  FParser.ParseFile(TPath.Combine(FRoot, 'Consumer.pas'));
  WriteSource('body.inc', 'type TChanged = Integer;');
  FParser.ParseFile(TPath.Combine(FRoot, 'Consumer.pas'));
  WriteSource('body.inc', 'type TIncluded = Integer;');
  Assert.WillRaise(procedure begin FSnapshot.ValidateAnalysis end, EInvalidOperation);
end;

procedure TAnalysisSnapshotTests.NewAnalysisResetsPriorSnapshot;
begin
  FParser.ParseFile(TPath.Combine(FRoot, 'Consumer.pas'));
  WriteSource('body.inc', 'type TChanged = Integer;');
  FSnapshot.BeginAnalysis;
  FParser.ParseFile(TPath.Combine(FRoot, 'Consumer.pas'));
  FSnapshot.ValidateAnalysis;
end;

procedure TAnalysisSnapshotTests.ResolvedProviderChangeInvalidatesSnapshot;
var
  LResolver: IExternalUnitResolver;
  LExports: TArray<string>;
  LHasInit, LNative: Boolean;
begin
  WriteSource('Provider.pas', 'unit Provider; interface type TExport = Integer; implementation end.');
  LResolver := TExternalUnitResolverAdapter.Create(FParser);
  LResolver.Initialize([FRoot], '', FRoot);
  Assert.IsTrue(LResolver.TryResolveUnit('Provider', LExports, LHasInit, LNative));
  WriteSource('Provider.pas', 'unit Provider; interface implementation end.');
  Assert.WillRaise(procedure begin FSnapshot.ValidateAnalysis end, EInvalidOperation);
end;

procedure TAnalysisSnapshotTests.RunPlanning(const AReject, ACancel, ADryRun: Boolean);
var
  LProject: TProjectParserSpy;
  LParser: TPlanningParserSpy;
  LFiles: TFileServiceSpy;
  LResolver: TExternalResolverStub;
  LReports: TReportGeneratorStub;
  LService: TProjectCleanerAppService;
  LConfig: TToolConfig;
  LCancelled: Boolean;
begin
  LProject := TProjectParserSpy.Create;
  LProject.Units := [WriteSource('First.pas', ''), WriteSource('Second.pas', '')];
  LFiles := TFileServiceSpy.Create;
  LFiles.Content := 'unit TestUnit; interface uses Unused.Unit; implementation end.';
  LParser := TPlanningParserSpy.Create;
  LParser.Files := LFiles;
  LParser.RejectValidation := AReject;
  LResolver := TExternalResolverStub.Create;
  LResolver.ResolveKnownUnits := True;
  LReports := TReportGeneratorStub.Create;
  LConfig := TToolConfig.Default;
  LConfig.RemoveUnused := True;
  LConfig.DryRun := ADryRun;
  LCancelled := False;
  LService := TProjectCleanerAppService.Create(LProject, LParser, LFiles,
    LReports, TDelphiEnvironmentStub.Create, LResolver,
    TSuccessfulBuildService.Create, LConfig,
    function: Boolean begin Result := LCancelled end);
  try
    LService.OnProgress := procedure(AMax, APosition: Integer)
      begin LCancelled := ACancel and (APosition = AMax) end;
    if AReject or ACancel then
      Assert.WillRaise(procedure begin LService.Execute(TPath.Combine(FRoot, 'Test.dproj')) end);
    if not (AReject or ACancel) then
      Assert.IsTrue(LService.Execute(TPath.Combine(FRoot, 'Test.dproj')));
    Assert.AreEqual(2, LParser.ParseCount);
    Assert.AreEqual(0, LParser.WritesDuringParsing);
    if not ACancel then
      Assert.AreEqual(1, LParser.ValidationCount);
    if AReject or ACancel or ADryRun then
    begin
      Assert.AreEqual(0, LFiles.WriteCallCount);
      Assert.AreEqual(0, LFiles.BackupCallCount);
    end;
    if AReject or ACancel then
      Assert.AreEqual(1, LFiles.RestoreCallCount);
    if not (AReject or ACancel or ADryRun) then
      Assert.IsTrue(LFiles.WriteCallCount > 0);
    if ADryRun then
      Assert.AreEqual(2, LReports.AddUnitCallCount);
  finally
    LService.Free;
  end;
end;

procedure TAnalysisSnapshotTests.EveryUnitIsAnalyzedBeforeFirstWrite;
begin RunPlanning(False, False, False) end;
procedure TAnalysisSnapshotTests.ValidationFailurePreventsAllWrites;
begin RunPlanning(True, False, False) end;
procedure TAnalysisSnapshotTests.CancellationAfterAnalysisPreventsAllWrites;
begin RunPlanning(False, True, False) end;
procedure TAnalysisSnapshotTests.DryRunConsumesTheSameValidatedPlan;
begin RunPlanning(False, False, True) end;

procedure TAnalysisSnapshotTests.RealDependencyIncludeChangeAbortsBeforeEditing;
var
  LProject: TProjectParserSpy;
  LService: TProjectCleanerAppService;
  LConfig: TToolConfig;
  LConsumer, LOriginal, LInclude: string;
begin
  LOriginal := 'unit Consumer; interface uses Provider; implementation end.';
  LConsumer := WriteSource('Consumer.pas', LOriginal);
  LInclude := WriteSource('provider.inc', '');
  WriteSource('Provider.pas', 'unit Provider; interface {$I provider.inc} implementation end.');
  LProject := TProjectParserSpy.Create;
  LProject.Units := [LConsumer];
  LConfig := TToolConfig.Default;
  LConfig.RemoveUnused := True;
  LService := TProjectCleanerAppService.Create(LProject, FParser,
    TFileSystemAdapter.Create, TReportGeneratorStub.Create,
    TDelphiEnvironmentStub.Create, TExternalUnitResolverAdapter.Create(FParser),
    TSuccessfulBuildService.Create, LConfig);
  try
    LService.OnProgress := procedure(AMax, APosition: Integer)
      begin
        if APosition = AMax then
          TFile.WriteAllText(LInclude, 'type TAdded = Integer;', TEncoding.UTF8);
      end;
    Assert.WillRaise(procedure begin LService.Execute(TPath.Combine(FRoot, 'Test.dproj')) end,
      EInvalidOperation);
    Assert.AreEqual(LOriginal, TFile.ReadAllText(LConsumer));
    Assert.AreEqual('type TAdded = Integer;', TFile.ReadAllText(LInclude));
    Assert.IsFalse(TFile.Exists(TPath.Combine(FRoot, '.atropos-transaction.json')));
  finally
    LService.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAnalysisSnapshotTests);

end.
