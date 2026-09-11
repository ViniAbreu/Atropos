unit Atropos.Tests.CompilerBranchTrace;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TCompilerBranchTraceTests = class
  public
    [TestCase('First', '0 1 3,First,Second')]
    [TestCase('Second', '0 2 3,Second,First')]
    procedure ReplaysSelectedBranch(const AIds, AKept, ARemoved: string);
    [TestCase('Empty', '')]
    [TestCase('Duplicate', '0 0')]
    [TestCase('OutOfOrder', '0 3 2')]
    [TestCase('OutOfRange', '0 4')]
    [TestCase('MissingEnd', '0 1')]
    [TestCase('BothAlternatives', '0 1 2 3')]
    [TestCase('MissingElse', '0 3')]
    procedure RejectsInvalidTrace(const AIds: string);
    [Test] procedure NestedInactiveBranchesKeepOffsets;
    [Test] procedure IncludesRequireInvocationTracking;
    [Test] procedure RepeatedIncludesHaveIndependentBranches;
    [Test] procedure ConditionalCanEndOutsideInclude;
    [Test] procedure InactiveMissingIncludeIsNotReplayed;
    [Test] procedure ParserConsumesRepeatedPreparedIncludes;
    [Test] procedure IncludeQueueRejectsUnexpectedConsumption;
  end;

implementation

uses System.SysUtils, System.Classes, Atropos.Adapters.CompilerBranchTrace,
  Atropos.Adapters.TracedIncludes, Atropos.Adapters.SyntaxBuilder,
  Atropos.Adapters.DelphiAST, Atropos.Core.Ports, SimpleParser.Lexer.Types;

const Source = 'unit Trial; interface {$IF Declared(Local)} const First=1; ' +
  '{$ELSE} const Second=2; {$ENDIF} implementation end.';

procedure TCompilerBranchTraceTests.IncludeQueueRejectsUnexpectedConsumption;
var LHandler: TTracedIncludes; LIncludes: TArray<TCompilerTraceInclude>; LContent, LPath: string;
begin
  SetLength(LIncludes, 1);
  LIncludes[0].Name := 'shared.inc';
  LIncludes[0].ParentPath := 'root.pas';
  LIncludes[0].SourcePath := 'original/shared.inc';
  LIncludes[0].Content := 'prepared';
  LHandler := TTracedIncludes.Create('root.pas', LIncludes);
  try
    Assert.WillRaise(procedure begin LHandler.ValidateConsumed end, EIncludeError);
    Assert.WillRaise(procedure begin
      LHandler.GetIncludeFileContent('other.pas', 'shared.inc', LContent, LPath);
    end, EIncludeError);
    Assert.WillRaise(procedure begin
      LHandler.GetIncludeFileContent('', 'wrong.inc', LContent, LPath);
    end, EIncludeError);
    Assert.IsTrue(LHandler.GetIncludeFileContent('', 'shared.inc', LContent, LPath));
    Assert.AreEqual('prepared', LContent);
    Assert.AreEqual('original/shared.inc', LPath);
    LHandler.ValidateConsumed;
    Assert.WillRaise(procedure begin
      LHandler.GetIncludeFileContent('', 'shared.inc', LContent, LPath);
    end, EIncludeError);
  finally
    LHandler.Free;
  end;
end;

procedure TCompilerBranchTraceTests.ParserConsumesRepeatedPreparedIncludes;
var LTrace: TCompilerBranchTrace; LId, LOutput, LPrepared: string;
  LHandler: TTracedIncludes; LPort: IIncludeHandler; LBuilder: TAtroposSyntaxBuilder;
  LStream: TStringStream; LTree: IUnitSyntaxTree;
begin
  LTrace := TCompilerBranchTrace.Create('unit Trial; interface ' +
    '{$DEFINE FIRST}{$I shared.inc}{$UNDEF FIRST}{$I shared.inc} implementation end.', 'root.pas',
    function(const AParent, AName: string; out AContent, APath: string): Boolean
    begin
      APath := 'shared.inc';
      AContent := '{$IFDEF FIRST}type TFirst=Integer;{$ELSE}type TSecond=Integer;{$ENDIF}';
      Result := True;
    end);
  try
    LOutput := '';
    for LId in '0 1 2 4 5 6 8 9 10'.Split([' ']) do
      LOutput := LOutput + LTrace.Prefix + LId + sLineBreak;
    LPrepared := LTrace.Replay(LOutput);
    LHandler := TTracedIncludes.Create('root.pas', LTrace.PreparedIncludes);
    LPort := LHandler;
    LBuilder := TAtroposSyntaxBuilder.Create;
    LStream := TStringStream.Create(LPrepared, TEncoding.UTF8);
    try
      LBuilder.IncludeHandler := LPort;
      LTree := TDelphiASTSyntaxTree.Create('root.pas', LBuilder.Run(LStream), []);
      LHandler.ValidateConsumed;
      Assert.Contains<string>(LTree.GetExportedIdentifiers, 'TFirst');
      Assert.Contains<string>(LTree.GetExportedIdentifiers, 'TSecond');
    finally
      LStream.Free;
      LBuilder.Free;
    end;
  finally
    LTrace.Free;
  end;
end;

procedure TCompilerBranchTraceTests.RepeatedIncludesHaveIndependentBranches;
var LTrace: TCompilerBranchTrace; LOutput, LId, LSource: string;
  LPrepared, LInstrumented: TArray<TCompilerTraceInclude>;
begin
  LSource := '{$DEFINE FIRST}{$I shared.inc}{$UNDEF FIRST}{$I shared.inc}';
  LTrace := TCompilerBranchTrace.Create(LSource, 'root.pas',
    function(const AParent, AName: string; out AContent, APath: string): Boolean
    begin
      APath := 'shared.inc';
      AContent := '{$IFDEF FIRST}First{$ELSE}Second{$ENDIF}';
      Result := True;
    end);
  try
    LOutput := '';
    for LId in '0 1 2 4 5 6 8 9 10'.Split([' ']) do
      LOutput := LOutput + LTrace.Prefix + LId + sLineBreak;
    Assert.AreEqual(LSource, LTrace.Replay(LOutput));
    LPrepared := LTrace.PreparedIncludes;
    Assert.AreEqual<NativeInt>(2, Length(LPrepared));
    Assert.Contains(LPrepared[0].Content, 'First');
    Assert.IsFalse(LPrepared[0].Content.Contains('Second'));
    Assert.Contains(LPrepared[1].Content, 'Second');
    Assert.IsFalse(LPrepared[1].Content.Contains('First'));
    Assert.AreEqual('shared.inc', LPrepared[0].SourcePath);
    Assert.AreEqual('root.pas', LPrepared[0].ParentPath);
    LInstrumented := LTrace.InstrumentedIncludes;
    Assert.AreNotEqual(LInstrumented[0].Name, LInstrumented[1].Name);
  finally
    LTrace.Free;
  end;
end;

procedure TCompilerBranchTraceTests.ConditionalCanEndOutsideInclude;
var LTrace: TCompilerBranchTrace; LResult: string;
begin
  LTrace := TCompilerBranchTrace.Create('{$I open.inc}Dropped{$ENDIF}', 'root.pas',
    function(const AParent, AName: string; out AContent, APath: string): Boolean
    begin AContent := '{$IF FALSE}'; APath := 'open.inc'; Result := True end);
  try
    LResult := LTrace.Replay(LTrace.Prefix + '0' + sLineBreak +
      LTrace.Prefix + '1' + sLineBreak + LTrace.Prefix + '4');
    Assert.IsFalse(LResult.Contains('Dropped'));
    Assert.AreEqual<NativeInt>(1, Length(LTrace.PreparedIncludes));
  finally
    LTrace.Free;
  end;
end;

procedure TCompilerBranchTraceTests.InactiveMissingIncludeIsNotReplayed;
var LTrace: TCompilerBranchTrace; LResult: string;
begin
  LTrace := TCompilerBranchTrace.Create('{$IF FALSE}{$I missing.inc}{$ENDIF}', 'root.pas',
    function(const AParent, AName: string; out AContent, APath: string): Boolean
    begin AContent := ''; APath := ''; Result := False end);
  try
    LResult := LTrace.Replay(LTrace.Prefix + '0' + sLineBreak + LTrace.Prefix + '4');
    Assert.IsFalse(LResult.Contains('missing.inc'));
    Assert.AreEqual<NativeInt>(0, Length(LTrace.PreparedIncludes));
  finally
    LTrace.Free;
  end;
end;

procedure TCompilerBranchTraceTests.ReplaysSelectedBranch(const AIds, AKept, ARemoved: string);
var LTrace: TCompilerBranchTrace; LOutput, LId, LResult: string;
begin
  LTrace := TCompilerBranchTrace.Create(Source);
  try
    LOutput := LTrace.Prefix + '999.inc(1) Hint: unrelated diagnostic' + sLineBreak;
    for LId in AIds.Split([' ']) do LOutput := LOutput + LTrace.Prefix + LId + sLineBreak;
    LResult := LTrace.Replay(LOutput);
    Assert.Contains(LResult, AKept);
    Assert.IsFalse(LResult.Contains(ARemoved));
    Assert.AreEqual(Length(Source), Length(LResult));
    Assert.Contains(LTrace.Instrument, '{$HINTS ON}{$MESSAGE HINT');
  finally
    LTrace.Free;
  end;
end;

procedure TCompilerBranchTraceTests.RejectsInvalidTrace(const AIds: string);
var LTrace: TCompilerBranchTrace; LOutput, LId: string;
begin
  LTrace := TCompilerBranchTrace.Create(Source);
  try
    LOutput := '';
    for LId in AIds.Split([' ']) do
      if not LId.IsEmpty then LOutput := LOutput + LTrace.Prefix + LId + sLineBreak;
    Assert.WillRaise(procedure begin LTrace.Replay(LOutput); end, EInvalidOpException);
  finally
    LTrace.Free;
  end;
end;

procedure TCompilerBranchTraceTests.NestedInactiveBranchesKeepOffsets;
var LTrace: TCompilerBranchTrace; LSource, LResult: string; I: Integer;
begin
  LSource := '{$IF FALSE}' + sLineBreak + '{$IF TRUE}Dropped{$ENDIF}' + sLineBreak +
    '{$ELSE}Kept{$ENDIF}';
  LTrace := TCompilerBranchTrace.Create(LSource);
  try
    LResult := LTrace.Replay(LTrace.Prefix + '0' + sLineBreak +
      LTrace.Prefix + '4' + sLineBreak + LTrace.Prefix + '5');
    Assert.AreEqual(Length(LSource), Length(LResult));
    for I := 1 to Length(LSource) do
      if CharInSet(LSource[I], [#10, #13]) then Assert.AreEqual(LSource[I], LResult[I]);
    Assert.Contains(LResult, 'Kept');
    Assert.IsFalse(LResult.Contains('Dropped'));
  finally
    LTrace.Free;
  end;
end;

procedure TCompilerBranchTraceTests.IncludesRequireInvocationTracking;
begin
  Assert.WillRaise(procedure
    var LTrace: TCompilerBranchTrace;
    begin
      LTrace := TCompilerBranchTrace.Create('{$I shared.inc}');
      LTrace.Free;
    end, EInvalidOpException);
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerBranchTraceTests);

end.
