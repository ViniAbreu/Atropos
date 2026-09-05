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
    procedure EnsureDirectory(const ADirectory: string);
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
    [Test]
    procedure RemoveOnlyUnitRemovesEmptyUsesClause;
    [Test]
    procedure RemoveFromImplementationKeepsInterfaceUses;
    [Test]
    procedure AddToInterfaceCreatesMissingUsesClause;
    [Test]
    procedure AddingExistingInterfaceUnitIsIdempotent;
    [Test]
    procedure AddToExistingInterfaceUses;
    [Test]
    procedure AddToConditionalImplementationCreatesUnconditionalUses;
    [Test]
    procedure MissingSectionOrSemicolonLeavesSourceUnchanged;
    [Test]
    procedure RemoveUnitAlsoRemovesInFileAlias;
    [Test]
    procedure UnitMentionedOnlyInCommentIsNotRemoved;
    [Test]
    procedure RemovingUnitDoesNotMatchQualifiedNames;
    [Test]
    procedure RemoveUnitWithTrailingCommentKeepsValidClause;
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

procedure TMockFileService.EnsureDirectory(const ADirectory: string);
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

procedure TApplyUsesChangesTests.RemoveOnlyUnitRemovesEmptyUsesClause;
var
  LSource: string;
  LResult: string;
begin
  LSource := 'unit Test;' + sLineBreak + 'interface' + sLineBreak +
    'uses Unit1;' + sLineBreak + 'implementation' + sLineBreak + 'end.';
  LResult := TApplyUsesChanges.RemoveUnitFromUsesClause(LSource, 'Unit1', True);
  Assert.IsFalse(LResult.Contains('uses Unit1'));
  Assert.IsFalse(LResult.Contains('uses;'));
end;

procedure TApplyUsesChangesTests.RemoveFromImplementationKeepsInterfaceUses;
var
  LSource: string;
  LResult: string;
begin
  LSource := 'unit Test;' + sLineBreak + 'interface' + sLineBreak +
    'uses SharedUnit;' + sLineBreak + 'implementation' + sLineBreak +
    'uses SharedUnit, RemoveUnit;' + sLineBreak + 'end.';
  LResult := TApplyUsesChanges.RemoveUnitFromUsesClause(LSource, 'RemoveUnit', False);
  Assert.IsTrue(LResult.Contains('uses SharedUnit;'));
  Assert.IsFalse(LResult.Contains('RemoveUnit'));
end;

procedure TApplyUsesChangesTests.AddToInterfaceCreatesMissingUsesClause;
var
  LSource: string;
  LResult: string;
begin
  LSource := 'unit Test;' + sLineBreak + 'interface' + sLineBreak +
    'type TSample = class end;' + sLineBreak + 'implementation' + sLineBreak + 'end.';
  LResult := TApplyUsesChanges.AddUnitToInterfaceUses(LSource, 'System.SysUtils');
  Assert.IsTrue(LResult.Contains('uses' + sLineBreak + '  System.SysUtils;'));
end;

procedure TApplyUsesChangesTests.AddingExistingInterfaceUnitIsIdempotent;
var
  LSource: string;
begin
  LSource := 'unit Test;' + sLineBreak + 'interface' + sLineBreak +
    'uses System.SysUtils;' + sLineBreak + 'implementation' + sLineBreak + 'end.';
  Assert.AreEqual(LSource,
    TApplyUsesChanges.AddUnitToInterfaceUses(LSource, 'System.SysUtils'));
end;

procedure TApplyUsesChangesTests.AddToExistingInterfaceUses;
var
  LSource: string;
  LResult: string;
begin
  LSource := 'unit Test;' + sLineBreak + 'interface' + sLineBreak +
    'uses SharedUnit;' + sLineBreak + 'implementation' + sLineBreak +
    'uses OtherUnit, SharedUnit;' + sLineBreak + 'end.';
  LResult := TApplyUsesChanges.AddUnitToInterfaceUses(LSource, 'AddedUnit');
  Assert.IsTrue(LResult.Contains('uses AddedUnit,'));
end;

procedure TApplyUsesChangesTests.AddToConditionalImplementationCreatesUnconditionalUses;
var
  LSource: string;
  LResult: string;
  LConfig: TToolConfig;
  LService: TMockFileService;
  LModifier: TApplyUsesChanges;
  LAnalysis: TUnitAnalysisResult;
begin
  LSource := 'unit Test;' + sLineBreak + 'interface' + sLineBreak +
    'uses MoveUnit;' + sLineBreak + 'implementation' + sLineBreak +
    '{$IFDEF WINDOWS}' + sLineBreak + 'uses Winapi.Windows;' + sLineBreak +
    '{$ENDIF}' + sLineBreak + 'end.';
  LConfig := TToolConfig.Default;
  LConfig.MoveToImplementation := True;
  LService := TMockFileService.Create(LSource);
  LModifier := TApplyUsesChanges.Create(LService, LConfig);
  try
    LAnalysis.UnusedUnits := [];
    LAnalysis.UnitsToMoveToImpl := ['MoveUnit'];
    LModifier.Execute('test.pas', LAnalysis);
    LResult := LService.Content;
    Assert.IsTrue(LResult.Contains('uses MoveUnit'));
    Assert.IsTrue(LResult.Contains('{$IFDEF WINDOWS}'));
    Assert.IsTrue(LResult.Contains('Winapi.Windows'));
  finally
    LModifier.Free;
  end;
end;

procedure TApplyUsesChangesTests.MissingSectionOrSemicolonLeavesSourceUnchanged;
var
  LSource: string;
begin
  LSource := 'unit Test; implementation end.';
  Assert.AreEqual(LSource,
    TApplyUsesChanges.RemoveUnitFromUsesClause(LSource, 'MissingUnit', True));
  Assert.AreEqual(LSource,
    TApplyUsesChanges.AddUnitToInterfaceUses(LSource, 'MissingUnit'));

  LSource := 'unit Test;' + sLineBreak + 'interface' + sLineBreak +
    'uses BrokenUnit' + sLineBreak + 'implementation' + sLineBreak + 'end.';
  Assert.AreEqual(LSource,
    TApplyUsesChanges.RemoveUnitFromUsesClause(LSource, 'BrokenUnit', True));
end;

procedure TApplyUsesChangesTests.RemoveUnitAlsoRemovesInFileAlias;
var
  LSource: string;
  LResult: string;
begin
  LSource := 'unit Test;' + sLineBreak + 'interface' + sLineBreak +
    'uses Local.Unit in ''src\Local.Unit.pas'', System.SysUtils;' + sLineBreak +
    'implementation' + sLineBreak + 'end.';
  LResult := TApplyUsesChanges.RemoveUnitFromUsesClause(LSource, 'Local.Unit', True);
  Assert.IsFalse(LResult.Contains('Local.Unit'));
  Assert.IsFalse(LResult.Contains('src\Local.Unit.pas'));
  Assert.IsTrue(LResult.Contains('uses System.SysUtils;'));
end;

procedure TApplyUsesChangesTests.UnitMentionedOnlyInCommentIsNotRemoved;
var
  LSource: string;
begin
  LSource := 'unit Test;' + sLineBreak + 'interface' + sLineBreak +
    'uses System.SysUtils, { Legacy.Unit was removed } System.Classes;' + sLineBreak +
    'implementation' + sLineBreak + 'end.';
  Assert.AreEqual(LSource,
    TApplyUsesChanges.RemoveUnitFromUsesClause(LSource, 'Legacy.Unit', True));
end;

procedure TApplyUsesChangesTests.RemovingUnitDoesNotMatchQualifiedNames;
var
  LSource: string;
begin
  LSource := 'unit Test;' + sLineBreak + 'interface' + sLineBreak +
    'uses Company.Core, Company.Core.UI;' + sLineBreak +
    'implementation' + sLineBreak + 'end.';
  Assert.AreEqual(LSource,
    TApplyUsesChanges.RemoveUnitFromUsesClause(LSource, 'Core', True));
end;

procedure TApplyUsesChangesTests.RemoveUnitWithTrailingCommentKeepsValidClause;
var
  LSource: string;
  LResult: string;
begin
  LSource := 'unit Test;' + sLineBreak + 'interface' + sLineBreak +
    'uses Legacy.Unit { compatibility only }, System.SysUtils;' + sLineBreak +
    'implementation' + sLineBreak + 'end.';
  LResult := TApplyUsesChanges.RemoveUnitFromUsesClause(LSource, 'Legacy.Unit', True);
  Assert.IsFalse(LResult.Contains('Legacy.Unit'));
  Assert.IsFalse(LResult.Contains('compatibility only'));
  Assert.IsTrue(LResult.Contains('uses System.SysUtils;'));
end;

initialization
  TDUnitX.RegisterTestFixture(TApplyUsesChangesTests);

end.

