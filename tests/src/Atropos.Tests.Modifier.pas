unit Atropos.Tests.Modifier;

interface
uses
  Atropos.Core.Ports, Atropos.Core.Domain, Atropos.Core.Modifier, Atropos.Core.Config, DUnitX.TestFramework, System.SysUtils;

type
  TMockFileService = class(TInterfacedObject, IFileService)
  private
    FContent: string;
    FBackupCalled: Boolean;
    FWriteCalled: Boolean;
  public
    constructor Create(const AInitialContent: string);
    procedure BackupFile(const AFilePath: string);
    procedure RestoreBackups;
    procedure CommitBackups;
    function ReadFileContent(const AFilePath: string): string;
    procedure WriteFileContent(const AFilePath: string; const AContent: string);
    
    property BackupCalled: Boolean read FBackupCalled;
    property WriteCalled: Boolean read FWriteCalled;
    property Content: string read FContent;
  end;

  [TestFixture]
  TApplyUsesChangesTests = class
  public
    [Test]
    [TestCase('Remove unused units', 'Should identify and remove units that are not used anywhere')]
    procedure Test_RemoveUnusedUnits;
    [Test]
    [TestCase('Move to implementation', 'Should move units only used in implementation to the implementation uses clause')]
    procedure Test_MoveToImplementation;
  end;

implementation

{ TMockFileService }

constructor TMockFileService.Create(const AInitialContent: string);
begin
  FContent := AInitialContent;
end;

procedure TMockFileService.BackupFile(const AFilePath: string);
begin
  FBackupCalled := True;
end;

procedure TMockFileService.RestoreBackups;
begin
end;

procedure TMockFileService.CommitBackups;
begin
end;

function TMockFileService.ReadFileContent(const AFilePath: string): string;
begin
  Result := FContent;
end;

procedure TMockFileService.WriteFileContent(const AFilePath, AContent: string);
begin
  FWriteCalled := True;
  FContent := AContent;
end;

{ TApplyUsesChangesTests }

procedure TApplyUsesChangesTests.Test_RemoveUnusedUnits;
var
  LService: TMockFileService;
  LModifier: TApplyUsesChanges;
  LResult: TUnitAnalysisResult;
  LConfig: TToolConfig;
begin
  LConfig := TToolConfig.Default;
  LConfig.RemoveUnused := True;

  LService := TMockFileService.Create(
    'unit Test;' + sLineBreak +
    'interface' + sLineBreak +
    'uses Unit1, Unit2, Unit3;' + sLineBreak +
    'implementation' + sLineBreak +
    'end.'
  );
  
  LModifier := TApplyUsesChanges.Create(LService, LConfig);
  try
    LResult.UnusedUnits := ['Unit2'];
    LResult.UnitsToMoveToImpl := [];
    
    LModifier.Execute('test.pas', LResult);
    
    Assert.IsTrue(LService.BackupCalled);
    Assert.IsTrue(LService.WriteCalled);
    Assert.IsTrue(LService.Content.Contains('uses Unit1, Unit3;'));
    Assert.IsFalse(LService.Content.Contains('Unit2'));
  finally
    LModifier.Free;
  end;
end;

procedure TApplyUsesChangesTests.Test_MoveToImplementation;
var
  LService: TMockFileService;
  LModifier: TApplyUsesChanges;
  LResult: TUnitAnalysisResult;
  LConfig: TToolConfig;
begin
  LConfig := TToolConfig.Default;
  LConfig.MoveToImplementation := True;

  LService := TMockFileService.Create(
    'unit Test;' + sLineBreak +
    'interface' + sLineBreak +
    'uses Unit1;' + sLineBreak +
    'implementation' + sLineBreak +
    'end.'
  );
  
  LModifier := TApplyUsesChanges.Create(LService, LConfig);
  try
    LResult.UnusedUnits := [];
    LResult.UnitsToMoveToImpl := ['Unit1'];
    
    LModifier.Execute('test.pas', LResult);
    
    // Interface uses should not have Unit1 anymore
    Assert.IsFalse(LService.Content.Contains('interface uses Unit1;'));
    // Implementation should have Unit1
    Assert.IsTrue(LService.Content.Contains('uses' + sLineBreak + '  Unit1;'));
  finally
    LModifier.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TApplyUsesChangesTests);

end.

