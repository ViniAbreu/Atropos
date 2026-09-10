unit Atropos.Tests.Integration;

interface
uses
  Atropos.Core.Ports, Atropos.Core.Domain, Atropos.Core.Modifier, Atropos.Core.Config,
  Atropos.Adapters.ProjectParser, Atropos.Adapters.DelphiAST,
  Atropos.Adapters.FileSystem, Atropos.Adapters.ReportGenerator,
  Atropos.Adapters.ExternalUnitResolver, System.SysUtils, DUnitX.TestFramework, System.IOUtils;

type
  [TestFixture]
  TIntegrationTests = class
  private
    FDummyProjPath: string;
    FUnitAPath: string;
    
    procedure RestoreUnitA;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    
    [Test]
    [TestCase('Full pipeline end-to-end', 'Should successfully execute the complete cleaning pipeline')]
    procedure Test_FullPipeline_EndToEnd;
  end;

implementation

procedure TIntegrationTests.RestoreUnitA;
var
  LBackupPath: string;
  LRecoveryService: IFileService;
  LManifestPath: string;
begin
  LManifestPath := TPath.Combine(TPath.GetDirectoryName(FUnitAPath),
    '.atropos-transaction.json');
  if TFile.Exists(LManifestPath) then
  begin
    LRecoveryService := TFileSystemAdapter.Create;
    LRecoveryService.RecoverPendingBackups(TPath.GetDirectoryName(FUnitAPath));
    LRecoveryService.CommitBackups;
  end;
  for LBackupPath in TDirectory.GetFiles(TPath.GetDirectoryName(FUnitAPath),
    ExtractFileName(FUnitAPath) + '.atropos-*.bak') do
  begin
    TFile.Copy(LBackupPath, FUnitAPath, True);
    TFile.Delete(LBackupPath);
  end;
end;

procedure TIntegrationTests.Setup;
var
  LBaseDir: string;
begin
  LBaseDir := TPath.GetFullPath('DummyProject');
  FDummyProjPath := TPath.Combine(LBaseDir, 'DummyProject.dproj');
  FUnitAPath := TPath.Combine(LBaseDir, 'UnitA.pas');
  
  if not TFile.Exists(FDummyProjPath) then
  begin
    LBaseDir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'DummyProject');
    FDummyProjPath := TPath.Combine(LBaseDir, 'DummyProject.dproj');
    FUnitAPath := TPath.Combine(LBaseDir, 'UnitA.pas');
  end;

  if not TFile.Exists(FDummyProjPath) then
  begin
    LBaseDir := TPath.GetFullPath('tests\DummyProject');
    FDummyProjPath := TPath.Combine(LBaseDir, 'DummyProject.dproj');
    FUnitAPath := TPath.Combine(LBaseDir, 'UnitA.pas');
  end;
  
  if not TFile.Exists(FDummyProjPath) then
  begin
    LBaseDir := TPath.GetFullPath('..\..\DummyProject');
    FDummyProjPath := TPath.Combine(LBaseDir, 'DummyProject.dproj');
    FUnitAPath := TPath.Combine(LBaseDir, 'UnitA.pas');
  end;
  
  RestoreUnitA; // Ensure clean state before test
end;

procedure TIntegrationTests.TearDown;
begin
  RestoreUnitA; // Restore after test
end;

procedure TIntegrationTests.Test_FullPipeline_EndToEnd;
var
  LProjectParser: IProjectParser;
  LASTParser: IASTParser;
  LFileService: IFileService;
  LReportGen: IReportGenerator;
  LResolver: IExternalUnitResolver;
  LContext: TProjectContext;
  LAnalyzer: TAnalyzeUnitUses;
  LModifier: TApplyUsesChanges;
  LResult: TUnitAnalysisResult;
  LSyntaxTree: IUnitSyntaxTree;
  LUnits: TArray<string>;
  LUnit, LResolvedPath, LBasePath: string;
  LContentAfter: string;
  LConfig: TToolConfig;
begin
  // Arrange
  Assert.IsTrue(TFile.Exists(FDummyProjPath), 'DummyProject.dproj not found');
  LBasePath := TPath.GetDirectoryName(FDummyProjPath);
  
  LProjectParser := TDprojParserAdapter.Create;
  LASTParser := TDelphiASTAdapter.Create;
  LFileService := TFileSystemAdapter.Create;
  LReportGen := TReportGeneratorAdapter.Create;
  
  LResolver := TExternalUnitResolverAdapter.Create(LASTParser);
  LResolver.Initialize(['.'], '', LBasePath);
  LContext := TProjectContext.Create(LResolver);
  LAnalyzer := TAnalyzeUnitUses.Create;
  
  LConfig := TToolConfig.Default;
  LConfig.RemoveUnused := True;
  LModifier := TApplyUsesChanges.Create(LFileService, LConfig);
  
  try
    // Act
    LContext.RegisterUnitExports('System.SysUtils', ['Exception', 'IntToStr']);
    LContext.RegisterUnitDependencies('System.SysUtils', []);
    LContext.RegisterUnitExports('System.Classes', ['TStringList', 'TComponent']);
    LContext.RegisterUnitDependencies('System.Classes', []);
    
    // In an integration test, we simulate what CLI does
    LUnits := LProjectParser.GetProjectUnits(FDummyProjPath);
    Assert.AreEqual(2, Integer(Length(LUnits)), 'Should find UnitA and UnitB');
    
    for LUnit in LUnits do
    begin
      LResolvedPath := TPath.Combine(LBasePath, LUnit);
      if SameText(ExtractFileName(LResolvedPath), 'UnitA.pas') then
      begin
        LSyntaxTree := LASTParser.ParseFile(LResolvedPath);
        LResult := LAnalyzer.Execute(LSyntaxTree, LContext);
        
        // Ensure the analyzer marked UnitB as unused
        Assert.IsTrue(Length(LResult.UnusedUnits) > 0, 'Should find unused units. Found: ' + IntToStr(Length(LResult.UnusedUnits)));
        var LContainsUnitB := False;
        for var LUnusedUnit in LResult.UnusedUnits do
          if SameText(LUnusedUnit, 'UnitB') then LContainsUnitB := True;
        Assert.IsTrue(LContainsUnitB, 'UnitB should be unused');
        
        // Execute physical modifier
        LModifier.Execute(LResolvedPath, LResult);
      end;
    end;
    
    // Assert
    // Check if backup exists
    Assert.AreEqual(1, Integer(Length(TDirectory.GetFiles(LBasePath,
      'UnitA.pas.atropos-*.bak'))), 'Atropos backup should be created');
    
    // Check if UnitB was physically removed from UnitA.pas
    LContentAfter := TFile.ReadAllText(FUnitAPath);
    Assert.IsFalse(LContentAfter.Contains('UnitB'), 'UnitB should have been surgically removed from UnitA.pas');
    Assert.IsTrue(LContentAfter.Contains('System.SysUtils'), 'System.SysUtils should be preserved');
    Assert.IsTrue(LContentAfter.Contains('System.Classes'), 'System.Classes should be preserved');
    
  finally
    LFileService.RestoreBackups;
    LAnalyzer.Free;
    LContext.Free;
    LModifier.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TIntegrationTests);

end.

