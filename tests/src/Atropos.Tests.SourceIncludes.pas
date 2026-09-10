unit Atropos.Tests.SourceIncludes;

interface

uses DUnitX.TestFramework, Atropos.Core.Ports;

type
  [TestFixture]
  TSourceIncludeTests = class
  private
    FRoot: string;
    function WriteSource(const AName, AText: string): string;
    function Parse(const AText: string;
      const AIncludePaths: TArray<string>): IUnitSyntaxTree;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure NestedIncludesRecordParentAndContentHash;
    [Test] procedure RepeatedGuardedIncludeIsNotACycle;
    [Test] procedure MissingActiveIncludeFailsExplicitly;
    [Test] procedure InactiveMissingIncludeIsNotLoaded;
    [Test] procedure IncludeCycleFailsExplicitly;
    [Test] procedure ConfiguredRelativeIncludePathIsUsed;
    [Test] procedure ParentDirectoryPrecedesConfiguredPaths;
    [Test] procedure QuotedIncludeNamesAndMultilineStringsAreSupported;
    [Test] procedure IncludedUsesArePreservedUntilSourceAwareEditing;
    [Test] procedure SourceHashesChangeWhenIncludeChanges;
    [Test] procedure RootMultilineLiteralRetainsFollowingSemicolon;
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils, System.Hash,
  Atropos.Adapters.DelphiAST, Atropos.Core.Domain;

procedure TSourceIncludeTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'Atropos-Include-' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
end;

procedure TSourceIncludeTests.TearDown;
begin
  if not TPath.GetFullPath(FRoot).StartsWith(
    TPath.Combine(TPath.GetTempPath, 'Atropos-Include-'), True) then
    raise Exception.Create('Refusing to remove a path outside the test directory.');
  TDirectory.Delete(FRoot, True);
end;

function TSourceIncludeTests.WriteSource(const AName, AText: string): string;
begin
  Result := TPath.Combine(FRoot, AName);
  TDirectory.CreateDirectory(TPath.GetDirectoryName(Result));
  TFile.WriteAllText(Result, AText, TEncoding.UTF8);
end;

function TSourceIncludeTests.Parse(const AText: string;
  const AIncludePaths: TArray<string>): IUnitSyntaxTree;
var
  LParser: IASTParser;
begin
  LParser := TDelphiASTAdapter.Create(AIncludePaths);
  Result := LParser.ParseFile(WriteSource('Consumer.pas', AText));
end;

procedure TSourceIncludeTests.NestedIncludesRecordParentAndContentHash;
var
  LTree: IUnitSyntaxTree;
  LSources: IUnitSourceDependencies;
  LDependencies: TArray<TSourceDependency>;
  LOuter: string;
  LInner: string;
begin
  LOuter := WriteSource('sub\outer.inc', '{$I inner.inc}');
  LInner := WriteSource('sub\inner.inc', 'type TIncluded = Integer;');
  LTree := Parse('unit Consumer; interface {$I sub/outer.inc} implementation end.', []);
  Assert.IsTrue(Supports(LTree, IUnitSourceDependencies, LSources));
  LDependencies := LSources.GetSourceDependencies;
  Assert.AreEqual<NativeInt>(2, Length(LDependencies));
  Assert.AreEqual(LOuter, LDependencies[1].ParentPath);
  Assert.AreEqual(LInner, LDependencies[1].FilePath);
  Assert.AreEqual(THashSHA2.GetHashStringFromFile(LInner), LDependencies[1].ContentHash);
  Assert.AreEqual('TIncluded', LTree.GetExportedIdentifiers[0]);
end;

procedure TSourceIncludeTests.RepeatedGuardedIncludeIsNotACycle;
var
  LTree: IUnitSyntaxTree;
  LSources: IUnitSourceDependencies;
begin
  WriteSource('guard.inc', '{$IFNDEF INCLUDED}{$DEFINE INCLUDED}' +
    'type TIncluded = Integer; {$ENDIF}');
  LTree := Parse('unit Consumer; interface {$I guard.inc} {$I guard.inc}' +
    ' implementation end.', []);
  Assert.AreEqual<NativeInt>(1, Length(LTree.GetExportedIdentifiers));
  Assert.IsTrue(Supports(LTree, IUnitSourceDependencies, LSources));
  Assert.AreEqual<NativeInt>(1, Length(LSources.GetSourceDependencies));
end;

procedure TSourceIncludeTests.MissingActiveIncludeFailsExplicitly;
begin
  Assert.WillRaise(
    procedure
    begin
      Parse('unit Consumer; interface {$I missing.inc} implementation end.', []);
    end, EASTParserException);
end;

procedure TSourceIncludeTests.InactiveMissingIncludeIsNotLoaded;
var
  LTree: IUnitSyntaxTree;
  LSources: IUnitSourceDependencies;
begin
  LTree := Parse('unit Consumer; interface {$IFDEF ATROPOS_NEVER_DEFINED}' +
    '{$I missing.inc}{$ENDIF} implementation end.', []);
  Assert.IsTrue(Supports(LTree, IUnitSourceDependencies, LSources));
  Assert.AreEqual<NativeInt>(0, Length(LSources.GetSourceDependencies));
end;

procedure TSourceIncludeTests.IncludeCycleFailsExplicitly;
begin
  WriteSource('first.inc', '{$I second.inc}');
  WriteSource('second.inc', '{$I first.inc}');
  Assert.WillRaise(
    procedure
    begin
      Parse('unit Consumer; interface {$I first.inc} implementation end.', []);
    end, EASTParserException);
end;

procedure TSourceIncludeTests.ConfiguredRelativeIncludePathIsUsed;
var
  LTree: IUnitSyntaxTree;
begin
  WriteSource('includes\definition.inc', 'type TFromPath = Integer;');
  LTree := Parse('unit Consumer; interface {$I definition.inc} implementation end.',
    ['missing', 'includes']);
  Assert.AreEqual('TFromPath', LTree.GetExportedIdentifiers[0]);
end;

procedure TSourceIncludeTests.ParentDirectoryPrecedesConfiguredPaths;
var
  LTree: IUnitSyntaxTree;
begin
  WriteSource('definition.inc', 'type TLocal = Integer;');
  WriteSource('includes\definition.inc', 'type TOther = Integer;');
  LTree := Parse('unit Consumer; interface {$I definition.inc} implementation end.',
    [TPath.Combine(FRoot, 'includes')]);
  Assert.AreEqual('TLocal', LTree.GetExportedIdentifiers[0]);
end;

procedure TSourceIncludeTests.QuotedIncludeNamesAndMultilineStringsAreSupported;
var
  LTree: IUnitSyntaxTree;
begin
  WriteSource('my includes\text.inc', 'const QueryText = ' + sLineBreak +
    '''''''' + sLineBreak + 'select * from data' + sLineBreak + ''''''';');
  LTree := Parse('unit Consumer; interface {$I ''my includes/text.inc''}' +
    ' implementation end.', []);
  Assert.AreEqual('QueryText', LTree.GetExportedIdentifiers[0]);
end;

procedure TSourceIncludeTests.IncludedUsesArePreservedUntilSourceAwareEditing;
var
  LTree: IUnitSyntaxTree;
  LContext: TProjectContext;
  LAnalyzer: TAnalyzeUnitUses;
  LResult: TUnitAnalysisResult;
begin
  WriteSource('imports.inc', 'uses Provider;');
  LTree := Parse('unit Consumer; interface {$I imports.inc} implementation end.', []);
  Assert.AreEqual('Provider', LTree.GetInterfaceUses[0]);
  LContext := TProjectContext.Create;
  LAnalyzer := TAnalyzeUnitUses.Create;
  try
    LContext.RegisterUnitExports('Provider', []);
    LResult := LAnalyzer.Execute(LTree, LContext);
    Assert.AreEqual<NativeInt>(0, Length(LResult.UnusedUnits));
    Assert.AreEqual<NativeInt>(0, Length(LResult.UnitsToMoveToImpl));
    Assert.IsTrue(LResult.PreservationReasons[0].Contains('include'));
  finally
    LAnalyzer.Free;
    LContext.Free;
  end;
end;

procedure TSourceIncludeTests.SourceHashesChangeWhenIncludeChanges;
var
  LTree: IUnitSyntaxTree;
  LSources: IUnitSourceDependencies;
  LOriginalHash: string;
begin
  WriteSource('definition.inc', 'type TFirst = Integer;');
  LTree := Parse('unit Consumer; interface {$I definition.inc} implementation end.', []);
  Assert.IsTrue(Supports(LTree, IUnitSourceDependencies, LSources));
  LOriginalHash := LSources.GetSourceDependencies[0].ContentHash;
  WriteSource('definition.inc', 'type TSecond = Integer;');
  LTree := Parse('unit Consumer; interface {$I definition.inc} implementation end.', []);
  Assert.IsTrue(Supports(LTree, IUnitSourceDependencies, LSources));
  Assert.AreNotEqual(LOriginalHash, LSources.GetSourceDependencies[0].ContentHash);
end;

procedure TSourceIncludeTests.RootMultilineLiteralRetainsFollowingSemicolon;
var
  LTree: IUnitSyntaxTree;
begin
  LTree := Parse('unit Consumer; interface' + sLineBreak +
    'const QueryText =' + sLineBreak + '''''''' + sLineBreak +
    'select * from data' + sLineBreak + ''''''';' + sLineBreak +
    'type TAfterLiteral = Integer; implementation end.', []);
  Assert.Contains<string>(LTree.GetExportedIdentifiers, 'QueryText');
  Assert.Contains<string>(LTree.GetExportedIdentifiers, 'TAfterLiteral');
end;

initialization
  TDUnitX.RegisterTestFixture(TSourceIncludeTests);

end.
