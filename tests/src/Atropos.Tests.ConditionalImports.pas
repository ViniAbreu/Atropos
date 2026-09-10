unit Atropos.Tests.ConditionalImports;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TConditionalImportTests = class
  public
    [Test] procedure CompleteQualifiedBranchesKeepEveryCandidate;
    [Test] procedure ConditionalSeparatorsDoNotSplitNames;
    [Test] [TestCase('Shared prefix', '0')] [TestCase('Shared suffix', '1')]
    [TestCase('Conditional suffix', '2')] [TestCase('Nested prefix', '3')]
    [TestCase('Empty prefix branch', '4')] [TestCase('Empty dotted branch', '5')]
    procedure PartialConditionalNamesRemainUnsupported(const ACase: Integer);
  end;
implementation
uses System.SysUtils, System.Classes, Atropos.Adapters.ConditionalImports;

procedure TConditionalImportTests.CompleteQualifiedBranchesKeepEveryCandidate;
var LScanner: TConditionalImportScanner; LNames: TArray<string>;
begin
  LScanner := TConditionalImportScanner.Create;
  try
    LNames := LScanner.Find('unit Test; interface uses Always, ' +
      '{$IFDEF A}Scope.First{$ELSEIF DEFINED(B)}Scope.Second{$ELSE}Scope.Third{$ENDIF}; implementation end.');
    Assert.AreEqual<NativeInt>(3, Length(LNames));
    Assert.Contains<string>(LNames, 'Scope.First');
    Assert.Contains<string>(LNames, 'Scope.Second');
    Assert.Contains<string>(LNames, 'Scope.Third');
    LNames := LScanner.Find('unit Other; interface uses Plain; implementation end.');
    Assert.AreEqual<NativeInt>(0, Length(LNames), 'A reused scanner must reset branch state');
  finally
    LScanner.Free;
  end;
end;

procedure TConditionalImportTests.ConditionalSeparatorsDoNotSplitNames;
var LScanner: TConditionalImportScanner; LNames: TArray<string>;
begin
  LScanner := TConditionalImportScanner.Create;
  try
    LNames := LScanner.Find('unit Test; interface uses Scope.Always' +
      '{$IFDEF A},Scope.Optional{$ENDIF},Scope.Last; implementation end.');
    Assert.AreEqual<NativeInt>(1, Length(LNames));
    Assert.AreEqual('Scope.Optional', LNames[0]);
  finally
    LScanner.Free;
  end;
end;

procedure TConditionalImportTests.PartialConditionalNamesRemainUnsupported(const ACase: Integer);
const CNames: array[0..5] of string = (
  'Scope.{$IFDEF A}First{$ELSE}Second{$ENDIF}',
  '{$IFDEF A}Scope{$ELSE}Other{$ENDIF}.Provider',
  'Scope{$IFDEF A}.First{$ENDIF}',
  '{$IFDEF A}Scope.{$IFDEF B}First{$ELSE}Second{$ENDIF}{$ELSE}Other.Provider{$ENDIF}',
  'Scope{$IFDEF A}{$ELSE}More{$ENDIF}',
  'Scope.{$IFDEF A}{$ELSE}Provider{$ENDIF}');
var LScanner: TConditionalImportScanner;
begin
  LScanner := TConditionalImportScanner.Create;
  try
    Assert.WillRaise(procedure
      begin LScanner.Find('unit Test; interface uses ' + CNames[ACase] + '; implementation end.') end,
      EInvalidOperation);
  finally
    LScanner.Free;
  end;
end;
initialization
  TDUnitX.RegisterTestFixture(TConditionalImportTests);
end.
