unit Atropos.Tests.UsesEditing;

interface

uses DUnitX.TestFramework, Atropos.Core.Domain, Atropos.Core.UsesEditPlan;

type
  [TestFixture]
  TUsesEditingTests = class
  private
    function Plan(const ASource: string; const AAnalysis: TUnitAnalysisResult): TUsesEditPlan;
  public
    [Test] procedure RemovesOnlyTheAuthorizedSection;
    [Test] procedure RemovesUnconditionalTailWithoutTouchingDirectives;
    [Test] procedure OriginalOffsetsIgnoreCommentsAndMultilineStrings;
    [TestCase('LF', '0')]
    [TestCase('CRLF', '1')]
    procedure MovesPreservePathsOrderAndLineEndings(ACrlf: Integer);
    [Test] procedure ExistingDestinationKeepsItsPosition;
    [Test] procedure DifferentPathMappingPreventsMovement;
    [Test] procedure ConditionalAndDuplicateOccurrencesAreUnknown;
    [Test] procedure ConflictingDecisionsNeverEdit;
    [TestCase('Unknown', '0')]
    [TestCase('Ambiguous', '1')]
    procedure PreservedDecisionRetainsItsActualReason(AAmbiguous: Integer);
    [TestCase('DisabledBranch', '0')]
    [TestCase('EnabledBranch', '1')]
    procedure GuardedDestinationRemainsValid(AEnabled: Integer);
    [Test] procedure CommentOnlyRemovalRetainsComments;
    [Test] procedure StalePlanFailsBeforeBackup;
    [Test] procedure NoOpDoesNotBackupOrWrite;
    [Test] procedure IntersectionKeepsSectionIdentity;
    [Test] procedure InlineHintRelocationIsAtomicAndIdempotent;
    [Test] procedure DryRunPreparesCandidatesWithoutApplyingThem;
    [TestCase('DefaultLF', '0,0')]
    [TestCase('DefaultCRLF', '0,1')]
    [TestCase('Utf8LF', '1,0')]
    [TestCase('Utf8CRLF', '1,1')]
    [TestCase('Utf8BomLF', '2,0')]
    [TestCase('Utf8BomCRLF', '2,1')]
    [TestCase('Utf16Bom', '3,1')]
    procedure FileEditsPreserveExactEncoding(AEncoding, ACrlf: Integer);
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils,
  Atropos.Core.Analysis, Atropos.Core.Config, Atropos.Core.Ports,
  Atropos.Core.Modifier, Atropos.Core.UsesSyntax, Atropos.Core.AnalysisIntersection,
  Atropos.Core.Compilation, Atropos.Adapters.DelphiAST,
  Atropos.Adapters.FileSystem, Atropos.Tests.Modifier;

procedure TUsesEditingTests.PreservedDecisionRetainsItsActualReason(AAmbiguous: Integer);
var LAnalysis: TUnitAnalysisResult; LPlan: TUsesEditPlan; LState: TDependencyState;
begin
  LState := dsUnknown;
  if AAmbiguous = 1 then LState := dsAmbiguous;
  LAnalysis := Default(TUnitAnalysisResult);
  LAnalysis.Decisions := [TDependencyDecision.Create('Keep', usInterface, LState, daPreserve,
    'Original dependency evidence.')];
  LPlan := Plan('unit C; interface uses Keep; implementation end.', LAnalysis);
  Assert.IsFalse(LPlan.HasChanges);
  Assert.AreEqual('Original dependency evidence.', LPlan.Analysis.Decisions[0].Reason);
  Assert.AreEqual(Ord(LState), Ord(LPlan.Analysis.Decisions[0].State));
  Assert.AreEqual<NativeInt>(0, Length(LPlan.Warnings));
end;

procedure TUsesEditingTests.RemovesUnconditionalTailWithoutTouchingDirectives;
var LAnalysis: TUnitAnalysisResult; LPlan: TUsesEditPlan; LSource: string;
begin
  LSource := 'unit Consumer; interface implementation uses Base, ' +
    '{$IFDEF FLAG} Optional, {$ENDIF} Keep, Erase; end.';
  LAnalysis := Default(TUnitAnalysisResult);
  LAnalysis.Decisions := [TDependencyDecision.Create('Erase', usImplementation, dsUnused, daRemove, '')];
  LPlan := Plan(LSource, LAnalysis);
  Assert.AreEqual(LSource.Replace(', Erase', ''), LPlan.Updated);
  LSource := 'unit Consumer; interface implementation uses Base, ' +
    '{$IFDEF FLAG} Optional, {$ENDIF} Erase; end.';
  LPlan := Plan(LSource, LAnalysis);
  Assert.AreEqual(LSource, LPlan.Updated);
end;

function TUsesEditingTests.Plan(const ASource: string; const AAnalysis: TUnitAnalysisResult): TUsesEditPlan;
var LPlanner: TUsesEditPlanner; LConfig: TToolConfig;
begin
  LConfig := TToolConfig.Default.WithRemoveUnused(True).WithMoveToImplementation(True);
  LPlanner := TUsesEditPlanner.Create(ASource, 'Consumer.pas', LConfig);
  try
    Result := LPlanner.Prepare(AAnalysis);
  finally
    LPlanner.Free;
  end;
end;

procedure TUsesEditingTests.RemovesOnlyTheAuthorizedSection;
var LAnalysis: TUnitAnalysisResult; LPlan: TUsesEditPlan;
begin
  LAnalysis := Default(TUnitAnalysisResult);
  LAnalysis.UnusedUnits := ['Shared']; // Stale legacy projection must not override decisions.
  LAnalysis.Decisions := [TDependencyDecision.Create('Shared', usInterface, dsUsed, daPreserve, 'Used'),
    TDependencyDecision.Create('Shared', usImplementation, dsUnused, daRemove, 'Unused')];
  LPlan := Plan('unit Consumer; interface uses Shared; implementation uses Shared, Keep; end.', LAnalysis);
  Assert.AreEqual('unit Consumer; interface uses Shared; implementation uses Keep; end.', LPlan.Updated);
  Assert.AreEqual<NativeInt>(1, Length(LPlan.Analysis.UnusedUnits));
end;

procedure TUsesEditingTests.OriginalOffsetsIgnoreCommentsAndMultilineStrings;
var LAnalysis: TUnitAnalysisResult; LPlan: TUsesEditPlan; LSource, LPrefix: string;
  LDecision: TDependencyDecision;
begin
  LPrefix := '{ interface uses Fake; implementation }' + #10 + 'unit Consumer; interface' + #10 +
    'const Text = ' + #10 + StringOfChar('''', 3) + #10 +
    'implementation' + #10 + 'uses Erase;' + #10 + StringOfChar('''', 3) + ';' + #10;
  LSource := LPrefix + 'implementation uses Erase, Keep; end.';
  LAnalysis := Default(TUnitAnalysisResult);
  LAnalysis.Decisions := [TDependencyDecision.Create('Erase', usImplementation, dsUnused, daRemove, '')];
  LPlan := Plan(LSource, LAnalysis);
  Assert.AreEqual(LPrefix + 'implementation uses Keep; end.', LPlan.Updated);
  LDecision := LPlan.Analysis.Decisions[0];
  Assert.AreEqual('Erase', Copy(LSource, LDecision.Occurrence.StartOffset,
    LDecision.Occurrence.EndOffset - LDecision.Occurrence.StartOffset));
  Assert.IsTrue(LDecision.Occurrence.StartOffset > Length(LPrefix));
  Assert.AreEqual('Consumer.pas', LDecision.Occurrence.FilePath);
end;

procedure TUsesEditingTests.MovesPreservePathsOrderAndLineEndings(ACrlf: Integer);
var LBreak, LSource: string; LAnalysis: TUnitAnalysisResult; LFirst, LSecond: TUsesEditPlan;
begin
  LBreak := #10;
  if ACrlf = 1 then LBreak := #13#10;
  LSource := 'unit Consumer;' + LBreak + 'interface' + LBreak +
    'uses Alpha in ''dir;old\Alpha.pas'', Beta;' + LBreak + 'implementation' + LBreak + 'end.';
  LAnalysis := Default(TUnitAnalysisResult);
  LAnalysis.UnitsToMoveToImpl := ['Beta', 'Alpha'];
  LFirst := Plan(LSource, LAnalysis);
  Assert.IsTrue(LFirst.Updated.Contains('Alpha in ''dir;old\Alpha.pas'''));
  Assert.IsTrue(Pos('Alpha', LFirst.Updated) < Pos('Beta', LFirst.Updated));
  if ACrlf = 0 then Assert.IsFalse(LFirst.Updated.Contains(#13));
  Assert.IsTrue(LFirst.Updated.EndsWith(LBreak + 'end.'));
  LSecond := Plan(LFirst.Updated, LAnalysis);
  Assert.AreEqual(LFirst.Updated, LSecond.Updated);
  Assert.IsFalse(LSecond.HasChanges);
end;

procedure TUsesEditingTests.ExistingDestinationKeepsItsPosition;
var LAnalysis: TUnitAnalysisResult; LPlan: TUsesEditPlan;
begin
  LAnalysis := Default(TUnitAnalysisResult);
  LAnalysis.UnitsToMoveToImpl := ['Move'];
  LPlan := Plan('unit C; interface uses Move; implementation uses Before, Move, After; end.', LAnalysis);
  Assert.IsTrue(LPlan.Updated.Contains('uses Before, Move, After;'));
  Assert.IsFalse(LPlan.Updated.Contains('interface uses'));
end;

procedure TUsesEditingTests.DifferentPathMappingPreventsMovement;
var LAnalysis: TUnitAnalysisResult; LPlan: TUsesEditPlan;
begin
  LAnalysis := Default(TUnitAnalysisResult);
  LAnalysis.UnitsToMoveToImpl := ['Move'];
  LPlan := Plan('unit C; interface uses Move in ''one.pas''; implementation uses Move in ''two.pas''; end.', LAnalysis);
  Assert.IsFalse(LPlan.HasChanges);
  Assert.AreEqual<NativeInt>(1, Length(LPlan.Warnings));
end;

procedure TUsesEditingTests.ConditionalAndDuplicateOccurrencesAreUnknown;
var LAnalysis: TUnitAnalysisResult; LPlan: TUsesEditPlan;
begin
  LAnalysis := Default(TUnitAnalysisResult);
  LAnalysis.Decisions := [TDependencyDecision.Create('Erase', usInterface, dsUnused, daRemove, '')];
  LPlan := Plan('unit C; interface uses {$IFDEF FLAG}Erase{$ELSE}Erase{$ENDIF}; implementation end.', LAnalysis);
  Assert.IsFalse(LPlan.HasChanges);
  Assert.AreEqual(Ord(dsUnknown), Ord(LPlan.Analysis.Decisions[0].State));
  LPlan := Plan('unit C; interface uses Erase, Erase; implementation end.', LAnalysis);
  Assert.IsFalse(LPlan.HasChanges);
  LPlan := Plan('unit C; interface {$IFDEF FLAG}uses Erase;{$ENDIF} implementation end.', LAnalysis);
  Assert.IsFalse(LPlan.HasChanges);
  Assert.IsFalse(LPlan.Analysis.Decisions[0].Occurrence.Condition.IsEmpty);
end;

procedure TUsesEditingTests.ConflictingDecisionsNeverEdit;
var LAnalysis: TUnitAnalysisResult; LPlan: TUsesEditPlan;
begin
  LAnalysis := Default(TUnitAnalysisResult);
  LAnalysis.Decisions := [TDependencyDecision.Create('Shared', usInterface, dsUnused, daRemove, ''),
    TDependencyDecision.Create('Shared', usInterface, dsUnknown, daPreserve, '')];
  LPlan := Plan('unit C; interface uses Shared; implementation end.', LAnalysis);
  Assert.IsFalse(LPlan.HasChanges);
end;

procedure TUsesEditingTests.GuardedDestinationRemainsValid(AEnabled: Integer);
var LAnalysis: TUnitAnalysisResult; LPlan: TUsesEditPlan; LPath: string;
  LParser: IASTParser; LTree: IUnitSyntaxTree; LContext: TProjectCompilationContext;
begin
  LAnalysis := Default(TUnitAnalysisResult);
  LAnalysis.UnitsToMoveToImpl := ['Move'];
  LPlan := Plan('unit C; interface uses Move; implementation' + #10 +
    '{$IFDEF FLAG} uses Other; {$ENDIF}' + #10 + 'end.', LAnalysis);
  Assert.IsTrue(LPlan.HasChanges);
  LContext := Default(TProjectCompilationContext);
  if AEnabled = 1 then LContext.Defines := ['FLAG'];
  LParser := TDelphiASTAdapter.Create(LContext, Default(TCompilerSymbols));
  LPath := TPath.Combine(TPath.GetTempPath, 'AtroposUses-' + TGUID.NewGuid.ToString + '.pas');
  try
    TFile.WriteAllText(LPath, LPlan.Updated, TEncoding.UTF8);
    LTree := LParser.ParseFile(LPath);
    Assert.AreEqual<NativeInt>(0, Length(LTree.GetInterfaceUses));
    Assert.Contains<string>(LTree.GetImplementationUses, 'Move');
    Assert.AreEqual<NativeInt>(AEnabled + 1, Length(LTree.GetImplementationUses));
  finally
    TFile.Delete(LPath);
  end;
end;

procedure TUsesEditingTests.CommentOnlyRemovalRetainsComments;
var LAnalysis: TUnitAnalysisResult; LPlan: TUsesEditPlan;
begin
  LAnalysis := Default(TUnitAnalysisResult);
  LAnalysis.UnusedUnits := ['Erase'];
  LPlan := Plan('unit C; interface uses { reason } Erase; implementation end.', LAnalysis);
  Assert.IsTrue(LPlan.Updated.Contains('{ reason }'));
  Assert.IsFalse(LPlan.Updated.Contains('uses'));
  Assert.IsFalse(LPlan.Updated.Contains('Erase'));
end;

procedure TUsesEditingTests.StalePlanFailsBeforeBackup;
var LFiles: IFileService; LMock: TMockFileService; LModifier: TApplyUsesChanges;
  LPlan: TUsesEditPlan; LAnalysis: TUnitAnalysisResult;
begin
  LMock := TMockFileService.Create('unit C; interface uses Erase; implementation end.');
  LFiles := LMock;
  LModifier := TApplyUsesChanges.Create(LFiles, TToolConfig.Default.WithRemoveUnused(True));
  try
    LAnalysis := Default(TUnitAnalysisResult);
    LAnalysis.UnusedUnits := ['Erase'];
    LPlan := LModifier.Prepare('C.pas', LAnalysis);
    LFiles.WriteFileContent('C.pas', LPlan.Original + ' { user edit }');
    Assert.WillRaise(procedure begin LModifier.ApplyPlan('C.pas', LPlan) end, EInvalidOperation);
    Assert.IsFalse(LMock.BackupCalled);
  finally
    LModifier.Free;
  end;
end;

procedure TUsesEditingTests.NoOpDoesNotBackupOrWrite;
var LFiles: IFileService; LMock: TMockFileService; LModifier: TApplyUsesChanges;
begin
  LMock := TMockFileService.Create('unit C; interface implementation end.');
  LFiles := LMock;
  LModifier := TApplyUsesChanges.Create(LFiles, TToolConfig.Default);
  try
    LModifier.Execute('C.pas', Default(TUnitAnalysisResult));
    Assert.IsFalse(LMock.BackupCalled);
    Assert.IsFalse(LMock.WriteCalled);
  finally
    LModifier.Free;
  end;
end;

procedure TUsesEditingTests.IntersectionKeepsSectionIdentity;
var LAnalysis, LCombined: TUnitAnalysisResult; LIntersection: TAnalysisIntersection; LPlan: TUsesEditPlan;
begin
  LAnalysis := Default(TUnitAnalysisResult);
  LAnalysis.Decisions := [TDependencyDecision.Create('Shared', usInterface, dsUsed, daPreserve, ''),
    TDependencyDecision.Create('Shared', usImplementation, dsUnused, daRemove, '')];
  LIntersection := TAnalysisIntersection.Create;
  try
    LIntersection.Include('Win32', LAnalysis);
    LIntersection.Include('Win64', LAnalysis);
    LCombined := LIntersection.Combined;
    LPlan := Plan('unit C; interface uses Shared; implementation uses Shared, Keep; end.', LCombined);
    Assert.AreEqual('unit C; interface uses Shared; implementation uses Keep; end.', LPlan.Updated);
    LAnalysis.Decisions[1].Action := daPreserve;
    LIntersection.Include('Other', LAnalysis);
    LPlan := Plan('unit C; interface uses Shared; implementation uses Shared, Keep; end.', LIntersection.Combined);
    Assert.IsFalse(LPlan.HasChanges);
  finally
    LIntersection.Free;
  end;
end;

procedure TUsesEditingTests.FileEditsPreserveExactEncoding(AEncoding, ACrlf: Integer);
var LEncoding: TEncoding; LPrefix, LSource, LExpected, LBreak, LDirectory, LPath: string;
  LBytes, LExpectedBytes, LPreamble: TBytes; LFiles: IFileService; LModifier: TApplyUsesChanges;
  LAnalysis: TUnitAnalysisResult;
begin
  LEncoding := TEncoding.Default;
  if AEncoding in [1, 2] then LEncoding := TEncoding.UTF8;
  if AEncoding = 3 then LEncoding := TEncoding.Unicode;
  LBreak := #10;
  if ACrlf = 1 then LBreak := #13#10;
  LPreamble := nil;
  if AEncoding >= 2 then LPreamble := LEncoding.GetPreamble;
  LPrefix := '{ a' + Char($00E7) + Char($00E3) + 'o }' + LBreak;
  LSource := LPrefix + 'unit C;' + LBreak + 'interface' + LBreak +
    'uses Keep, Erase;' + LBreak + 'implementation' + LBreak + 'end.' + LBreak;
  LExpected := LSource.Replace(', Erase', '');
  LBytes := LPreamble + LEncoding.GetBytes(LSource);
  LExpectedBytes := LPreamble + LEncoding.GetBytes(LExpected);
  LDirectory := TPath.Combine(TPath.GetTempPath, 'AtroposEdit-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(LDirectory);
  LPath := TPath.Combine(LDirectory, 'C.pas');
  LFiles := TFileSystemAdapter.Create;
  LModifier := TApplyUsesChanges.Create(LFiles, TToolConfig.Default.WithRemoveUnused(True));
  try
    TFile.WriteAllBytes(LPath, LBytes);
    LAnalysis := Default(TUnitAnalysisResult);
    LAnalysis.Decisions := [TDependencyDecision.Create('Erase', usInterface, dsUnused, daRemove, '')];
    LModifier.Execute(LPath, LAnalysis);
    LFiles.CommitBackups;
    LBytes := TFile.ReadAllBytes(LPath);
    Assert.AreEqual<NativeInt>(Length(LExpectedBytes), Length(LBytes));
    Assert.IsTrue(CompareMem(@LExpectedBytes[0], @LBytes[0], Length(LBytes)));
    LModifier.Execute(LPath, LAnalysis);
    LBytes := TFile.ReadAllBytes(LPath);
    Assert.AreEqual<NativeInt>(Length(LExpectedBytes), Length(LBytes));
    Assert.IsTrue(CompareMem(@LExpectedBytes[0], @LBytes[0], Length(LBytes)));
  finally
    LModifier.Free;
    LFiles := nil;
    TDirectory.Delete(LDirectory, True);
  end;
end;

procedure TUsesEditingTests.InlineHintRelocationIsAtomicAndIdempotent;
var LSource, LUpdated: string;
begin
  LSource := 'unit C; interface implementation uses HintUnit in ''hint.pas''; end.';
  LUpdated := TApplyUsesChanges.EnsureInterfaceImport(LSource, 'HintUnit');
  Assert.IsTrue(LUpdated.Contains('HintUnit in ''hint.pas'''));
  Assert.IsFalse(LUpdated.Contains('implementation uses'));
  Assert.AreEqual(LUpdated, TApplyUsesChanges.EnsureInterfaceImport(LUpdated, 'HintUnit'));
  LSource := 'unit C; interface uses {$I Imports.inc} Keep; implementation uses HintUnit; end.';
  Assert.AreEqual(LSource, TApplyUsesChanges.EnsureInterfaceImport(LSource, 'HintUnit'));
  LSource := 'unit C; interface (*$INCLUDE Imports.inc*) implementation uses HintUnit; end.';
  Assert.AreEqual(LSource, TApplyUsesChanges.EnsureInterfaceImport(LSource, 'HintUnit'));
  LSource := 'unit C; interface {$I Imports.inc} implementation end.';
  Assert.AreEqual(LSource, TApplyUsesChanges.EnsureInterfaceImport(LSource, 'HintUnit'));
end;

procedure TUsesEditingTests.DryRunPreparesCandidatesWithoutApplyingThem;
var LFiles: IFileService; LMock: TMockFileService; LModifier: TApplyUsesChanges;
  LConfig: TToolConfig; LAnalysis: TUnitAnalysisResult; LPlan: TUsesEditPlan;
begin
  LConfig := TToolConfig.Default;
  LConfig.DryRun := True;
  LMock := TMockFileService.Create('unit C; interface uses Erase; implementation end.');
  LFiles := LMock;
  LModifier := TApplyUsesChanges.Create(LFiles, LConfig);
  try
    LAnalysis := Default(TUnitAnalysisResult);
    LAnalysis.UnusedUnits := ['Erase'];
    LPlan := LModifier.Prepare('C.pas', LAnalysis);
    Assert.IsTrue(LPlan.HasChanges);
    LModifier.ApplyPlan('C.pas', LPlan);
    Assert.IsFalse(LMock.BackupCalled);
    Assert.IsFalse(LMock.WriteCalled);
  finally
    LModifier.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesEditingTests);
end.
