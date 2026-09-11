unit Atropos.Tests.CompilerParser;

interface

uses DUnitX.TestFramework, Atropos.Core.Ports, Atropos.Adapters.CompilerPreparation;

type
  TStubCompilerPreparer = class(TInterfacedObject, ICompilerSourcePreparer)
  public
    Calls: Integer;
    Cancelled, WrongHash, Failed: Boolean;
    Output: TCompilerPreparedSource;
    function Prepare(const AFilePath, AExpectedHash: string): TCompilerPreparedSource;
  end;

  [TestFixture]
  TCompilerParserTests = class
  private
    FDirectory, FPath: string;
    FParser: IASTParser;
    FPreparer: TStubCompilerPreparer;
    procedure WriteSource(const ACondition: string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [TestCase('Declared', 'Declared(LocalType)')]
    [TestCase('SizeOf', 'SizeOf(LocalType)=1')]
    [TestCase('RtlVersion', 'RTLVersion>0')]
    procedure CompilerResultReachesParser(const ACondition: string);
    [Test] procedure OrdinaryConditionalDoesNotInvokeCompiler;
    [Test] procedure MalformedConditionalDoesNotInvokeCompiler;
    [Test] procedure ChangedSourceIsRejected;
    [Test] procedure CancellationPropagates;
    [Test] procedure CompilerFailureDoesNotProduceTree;
    [Test] procedure UnconsumedIncludesAreRejected;
    [Test] procedure DependenciesParticipateInSnapshot;
    [Test] procedure MissingCandidatesParticipateInSnapshot;
    [Test] procedure CompilerInputRetainsMultilineStrings;
  end;

implementation

uses System.SysUtils, System.IOUtils, System.Classes, System.Hash,
  Atropos.Core.Compilation, Atropos.Adapters.DelphiAST, Atropos.Adapters.DelphiSource;

function TStubCompilerPreparer.Prepare(const AFilePath, AExpectedHash: string): TCompilerPreparedSource;
begin
  Inc(Calls);
  if Cancelled then raise EAbort.Create('Compiler preparation cancelled.');
  if Failed then raise EInvalidOpException.Create('Compiler failed.');
  Result := Output;
  Result.SourceHash := AExpectedHash;
  if WrongHash then Result.SourceHash := 'changed';
end;

procedure TCompilerParserTests.Setup;
var LContext: TProjectCompilationContext; LSymbols: TCompilerSymbols;
begin
  FDirectory := TPath.Combine(TPath.GetTempPath, 'Atropos-CompilerParser-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDirectory);
  FPath := TPath.Combine(FDirectory, 'Trial.pas');
  FPreparer := TStubCompilerPreparer.Create;
  FPreparer.Output.Text := 'unit Trial; interface type Selected=Integer; implementation end.';
  LContext := Default(TProjectCompilationContext);
  LSymbols := Default(TCompilerSymbols);
  LSymbols.CompilerVersion := '36.0';
  FParser := TDelphiASTAdapter.Create(LContext, LSymbols, FPreparer);
end;

procedure TCompilerParserTests.TearDown;
begin
  FParser := nil;
  TDirectory.Delete(FDirectory, True);
end;

procedure TCompilerParserTests.WriteSource(const ACondition: string);
begin
  TFile.WriteAllText(FPath, 'unit Trial; interface type LocalType=Byte; {$IF ' +
    ACondition + '}type First=Integer;{$ELSE}type Second=Integer;{$ENDIF} implementation end.', TEncoding.UTF8);
end;

procedure TCompilerParserTests.CompilerResultReachesParser(const ACondition: string);
var LTree: IUnitSyntaxTree;
begin
  WriteSource(ACondition);
  LTree := FParser.ParseFile(FPath);
  Assert.AreEqual(1, FPreparer.Calls);
  Assert.Contains<string>(LTree.GetExportedIdentifiers, 'Selected');
  Assert.IsFalse(string.Join(',', LTree.GetExportedIdentifiers).Contains('First'));
end;

procedure TCompilerParserTests.OrdinaryConditionalDoesNotInvokeCompiler;
var LTree: IUnitSyntaxTree;
begin
  WriteSource('TRUE');
  LTree := FParser.ParseFile(FPath);
  Assert.AreEqual(0, FPreparer.Calls);
  Assert.Contains<string>(LTree.GetExportedIdentifiers, 'First');
end;

procedure TCompilerParserTests.MalformedConditionalDoesNotInvokeCompiler;
begin
  WriteSource('(TRUE');
  Assert.WillRaise(procedure begin FParser.ParseFile(FPath) end, EASTParserException);
  Assert.AreEqual(0, FPreparer.Calls);
end;

procedure TCompilerParserTests.ChangedSourceIsRejected;
begin
  WriteSource('Declared(LocalType)');
  FPreparer.WrongHash := True;
  Assert.WillRaise(procedure begin FParser.ParseFile(FPath) end, EASTParserException);
  Assert.AreEqual(1, FPreparer.Calls);
end;

procedure TCompilerParserTests.CancellationPropagates;
begin
  WriteSource('Declared(LocalType)');
  FPreparer.Cancelled := True;
  Assert.WillRaise(procedure begin FParser.ParseFile(FPath) end, EAbort);
end;

procedure TCompilerParserTests.CompilerFailureDoesNotProduceTree;
begin
  WriteSource('Declared(LocalType)');
  FPreparer.Failed := True;
  Assert.WillRaise(procedure begin FParser.ParseFile(FPath) end, EASTParserException);
end;

procedure TCompilerParserTests.UnconsumedIncludesAreRejected;
begin
  WriteSource('Declared(LocalType)');
  SetLength(FPreparer.Output.Includes, 1);
  FPreparer.Output.Includes[0].Name := 'unconsumed.inc';
  Assert.WillRaise(procedure begin FParser.ParseFile(FPath) end, EASTParserException);
end;

procedure TCompilerParserTests.DependenciesParticipateInSnapshot;
var LSnapshot: IAnalysisSnapshot; LDependency: string; LTree: IUnitSyntaxTree;
  LDependencies: IUnitSourceDependencies;
begin
  WriteSource('Declared(LocalType)');
  LDependency := TPath.Combine(FDirectory, 'dependency.dcu');
  TFile.WriteAllText(LDependency, 'first');
  SetLength(FPreparer.Output.Dependencies, 1);
  FPreparer.Output.Dependencies[0].FilePath := LDependency;
  FPreparer.Output.Dependencies[0].ContentHash := THashSHA2.GetHashStringFromFile(LDependency);
  Assert.IsTrue(Supports(FParser, IAnalysisSnapshot, LSnapshot));
  LSnapshot.BeginAnalysis;
  LTree := FParser.ParseFile(FPath);
  Assert.IsTrue(Supports(LTree, IUnitSourceDependencies, LDependencies));
  Assert.AreEqual(LDependency, LDependencies.GetSourceDependencies[0].FilePath);
  LSnapshot.ValidateAnalysis;
  TFile.WriteAllText(LDependency, 'second');
  Assert.WillRaise(procedure begin LSnapshot.ValidateAnalysis end, EInvalidOperation);
end;

procedure TCompilerParserTests.MissingCandidatesParticipateInSnapshot;
var LSnapshot: IAnalysisSnapshot; LMissing: string;
begin
  WriteSource('Declared(LocalType)');
  LMissing := TPath.Combine(FDirectory, 'candidate.dcu');
  FPreparer.Output.MissingPaths := [LMissing];
  Assert.IsTrue(Supports(FParser, IAnalysisSnapshot, LSnapshot));
  LSnapshot.BeginAnalysis;
  FParser.ParseFile(FPath);
  LSnapshot.ValidateAnalysis;
  TFile.WriteAllText(LMissing, 'new dependency');
  Assert.WillRaise(procedure begin LSnapshot.ValidateAnalysis end, EInvalidOperation);
end;

procedure TCompilerParserTests.CompilerInputRetainsMultilineStrings;
var LText: string; LRaw, LNormalized: TDelphiSourceContent;
begin
  LText := 'unit Trial; interface const Text =' + sLineBreak +
    StringOfChar('''', 3) + sLineBreak + 'original compiler content' + sLineBreak +
    StringOfChar('''', 3) + '; implementation end.';
  TFile.WriteAllText(FPath, LText, TEncoding.UTF8);
  LRaw := TDelphiSourceReader.ReadRaw(FPath);
  LNormalized := TDelphiSourceReader.Read(FPath);
  Assert.AreEqual(LText, LRaw.Text);
  Assert.IsFalse(LNormalized.Text.Contains('original compiler content'));
  Assert.AreEqual(LRaw.ContentHash, LNormalized.ContentHash);
  Assert.AreEqual(THashSHA2.GetHashStringFromFile(FPath), LRaw.ContentHash);
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerParserTests);

end.
