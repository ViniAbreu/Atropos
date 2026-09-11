unit Atropos.Tests.Domain;

interface
uses
  Atropos.Core.HelperBinding, Atropos.Core.Ports, Atropos.Core.Domain, DUnitX.TestFramework;

type
  { Mock AST }
  TMockSyntaxTree = class(TInterfacedObject, IUnitSyntaxTree, IUnitMemberReferences)
  public
    UnitName: string;
    IntfUses: TArray<string>;
    ImplUses: TArray<string>;
    IntfIdents: TArray<string>;
    ImplIdents: TArray<string>;
    Members: TArray<TMemberReference>;
    function GetMemberReferences: TArray<TMemberReference>;
    
    function GetUnitName: string;
    function GetInterfaceUses: TArray<string>;
    function GetImplementationUses: TArray<string>;
    function GetIdentifiersUsedInInterface: TArray<string>;
    function GetIdentifiersUsedInImplementation: TArray<string>;
    function GetExportedIdentifiers: TArray<string>;
    function HasInitializationSection: Boolean;
  end;

  [TestFixture]
  TDomainTests = class
  private
    FContext: TProjectContext;
    FAnalyzer: TAnalyzeUnitUses;
  public
    [Test] procedure MissingMemberFactsCannotProveHelperUnused;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    
    [Test]
    [TestCase('Remove unused and move to implementation', 'Should remove unused units and move implementation-only units to the implementation section')]
    procedure Test_RemoveUnused_And_MoveToImpl;
    [Test]
    procedure HelpersAndQualifiedIdentifiersAreResolved;
    [Test]
    procedure InitializationUnitsArePreservedIncludingNative;
    [Test]
    procedure CollidingUnqualifiedIdentifierPreservesEveryCandidate;
    [Test]
    procedure QualifiedIdentifierPreservesOnlyNamedUnit;
    [Test]
    procedure UniqueIdentifierDoesNotPreserveUnrelatedUnit;
    [Test]
    procedure ImplementationHelperUsesReceiverTypeDeclaredInInterface;
  end;

implementation

procedure TDomainTests.MissingMemberFactsCannotProveHelperUnused;
begin
  FContext.RegisterUnitExports('Helpers', ['!HELPER:Twist:string']);
  Assert.AreEqual(Ord(huUnknown), Ord(FContext.AssessHelpers('Helpers',
    ['Helpers'], [], False, False)));
end;

function TMockSyntaxTree.GetMemberReferences: TArray<TMemberReference>;
begin
  Result := Members;
end;

{ TMockSyntaxTree }

function TMockSyntaxTree.GetIdentifiersUsedInImplementation: TArray<string>;
begin
  Result := ImplIdents;
end;

function TMockSyntaxTree.GetExportedIdentifiers: TArray<string>;
begin
  Result := []; // For the mock used in these tests, we don't strictly need to return exports
end;

function TMockSyntaxTree.GetIdentifiersUsedInInterface: TArray<string>;
begin
  Result := IntfIdents;
end;

function TMockSyntaxTree.GetImplementationUses: TArray<string>;
begin
  Result := ImplUses;
end;

function TMockSyntaxTree.GetInterfaceUses: TArray<string>;
begin
  Result := IntfUses;
end;

function TMockSyntaxTree.GetUnitName: string;
begin
  Result := UnitName;
end;

function TMockSyntaxTree.HasInitializationSection: Boolean;
begin
  Result := False; // Por padrão, o mock retorna false para facilitar os testes
end;

{ TDomainTests }

procedure TDomainTests.Setup;
begin
  FContext := TProjectContext.Create;
  FAnalyzer := TAnalyzeUnitUses.Create;
end;

procedure TDomainTests.TearDown;
begin
  FAnalyzer.Free;
  FContext.Free;
end;

procedure TDomainTests.Test_RemoveUnused_And_MoveToImpl;
var
  LMockTreeObj: TMockSyntaxTree;
  LMockTree: IUnitSyntaxTree;
  LResult: TUnitAnalysisResult;
begin
  // Register known exports
  FContext.RegisterUnitExports('System.SysUtils', ['Exception', 'IntToStr']);
  FContext.RegisterUnitDependencies('System.SysUtils', []);
  FContext.RegisterUnitExports('System.Classes', ['TStringList', 'TComponent']);
  FContext.RegisterUnitDependencies('System.Classes', []);
  FContext.RegisterUnitExports('Vcl.Forms', ['TForm']);
  FContext.RegisterUnitDependencies('Vcl.Forms', []);

  // Build Mock Tree
  LMockTreeObj := TMockSyntaxTree.Create;
  LMockTree := LMockTreeObj;
  LMockTreeObj.UnitName := 'Unit1';
  // Uses na Interface: SysUtils, Classes, Forms
  LMockTreeObj.IntfUses := ['System.SysUtils', 'System.Classes', 'Vcl.Forms'];
  LMockTreeObj.ImplUses := [];
  
  // Usamos Exception e TStringList na interface. Logo SysUtils e Classes devem ficar.
  LMockTreeObj.IntfIdents := ['Exception', 'TStringList'];
  
  // Usamos TForm APENAS na implementation. Logo Vcl.Forms deve ser MOVIDA.
  LMockTreeObj.ImplIdents := ['TForm'];

  LResult := FAnalyzer.Execute(LMockTree, FContext);

  // Asserts
  // Forms deve ter sido movida
  Assert.AreEqual(1, Integer(Length(LResult.UnitsToMoveToImpl)));
  Assert.AreEqual<string>('Vcl.Forms', LResult.UnitsToMoveToImpl[0]);
  
  // Nenhuma foi "completamente não usada" neste cenário, oh wait, TForm was used.
  // Vamos adicionar uma não usada:
  FContext.RegisterUnitExports('UnusedUnit', ['SomeDummyExport']);
  FContext.RegisterUnitDependencies('UnusedUnit', []);
  LMockTreeObj.IntfUses := ['System.SysUtils', 'System.Classes', 'Vcl.Forms', 'UnusedUnit'];
  LResult := FAnalyzer.Execute(LMockTree, FContext);
  
  Assert.AreEqual(1, Integer(Length(LResult.UnusedUnits)));
  Assert.AreEqual<string>('UnusedUnit', LResult.UnusedUnits[0]);
end;

procedure TDomainTests.HelpersAndQualifiedIdentifiersAreResolved;
begin
  FContext.RegisterUnitExports('Helper.Unit', [
    '!HELPER:ToText:string',
    'TArray']);
  FContext.RegisterUnitDependencies('Helper.Unit', []);

  Assert.IsTrue(FContext.UnitExportsIdentifier('Helper.Unit', 'ToText', ['string']));
  Assert.IsTrue(FContext.UnitExportsIdentifier('Helper.Unit', 'System.TArray<string>', []));
  Assert.IsFalse(FContext.UnitExportsIdentifier('Helper.Unit', 'UnknownIdentifier', []));
end;

procedure TDomainTests.InitializationUnitsArePreservedIncludingNative;
begin
  FContext.RegisterUnitExports('SideEffect.Unit', [], True, False);
  FContext.RegisterUnitDependencies('SideEffect.Unit', []);
  FContext.RegisterUnitExports('Native.Unit', [], True, True);
  FContext.RegisterUnitDependencies('Native.Unit', []);

  Assert.IsTrue(FContext.UnitHasInitialization('SideEffect.Unit'));
  Assert.IsTrue(FContext.UnitHasInitialization('Native.Unit'));
  Assert.IsFalse(FContext.UnitHasInitialization('Missing.Unit'));
end;

procedure TDomainTests.ImplementationHelperUsesReceiverTypeDeclaredInInterface;
var
  LSyntaxTree: TMockSyntaxTree;
  LResult: TUnitAnalysisResult;
begin
  FContext.RegisterUnitExports('System.SysUtils', [
    '!HELPER:ToString:SmallInt']);
  FContext.RegisterUnitDependencies('System.SysUtils', []);
  LSyntaxTree := TMockSyntaxTree.Create;
  LSyntaxTree.UnitName := 'SegmentosClientes';
  LSyntaxTree.IntfUses := ['System.SysUtils'];
  LSyntaxTree.IntfIdents := ['ACodSegm', 'SmallInt'];
  LSyntaxTree.ImplIdents := ['ACodSegm', 'ToString'];
  SetLength(LSyntaxTree.Members, 1);
  LSyntaxTree.Members[0].MemberName := 'ToString';
  LSyntaxTree.Members[0].ReceiverType := 'SmallInt';
  LResult := FAnalyzer.Execute(LSyntaxTree, FContext);
  Assert.AreEqual(0, Integer(Length(LResult.UnusedUnits)));
  Assert.AreEqual(1, Integer(Length(LResult.UnitsToMoveToImpl)));
  Assert.AreEqual('System.SysUtils', LResult.UnitsToMoveToImpl[0]);
end;

procedure TDomainTests.CollidingUnqualifiedIdentifierPreservesEveryCandidate;
var
  LSyntaxTree: TMockSyntaxTree;
  LResult: TUnitAnalysisResult;
begin
  FContext.RegisterUnitExports('First.Unit', ['TShared']);
  FContext.RegisterUnitDependencies('First.Unit', []);
  FContext.RegisterUnitExports('Second.Unit', ['TShared']);
  FContext.RegisterUnitDependencies('Second.Unit', []);
  LSyntaxTree := TMockSyntaxTree.Create;
  LSyntaxTree.UnitName := 'Consumer.Unit';
  LSyntaxTree.IntfUses := ['Second.Unit', 'First.Unit'];
  LSyntaxTree.IntfIdents := ['TShared'];
  LResult := FAnalyzer.Execute(LSyntaxTree, FContext);
  Assert.AreEqual(0, Integer(Length(LResult.UnusedUnits)));
  Assert.AreEqual(1, Integer(Length(LResult.PreservedAmbiguities)));
  Assert.IsTrue(Pos('TShared', LResult.PreservedAmbiguities[0]) > 0);
  Assert.IsTrue(Pos('First.Unit', LResult.PreservedAmbiguities[0]) > 0);
  Assert.IsTrue(Pos('Second.Unit', LResult.PreservedAmbiguities[0]) > 0);
end;

procedure TDomainTests.QualifiedIdentifierPreservesOnlyNamedUnit;
var
  LSyntaxTree: TMockSyntaxTree;
  LResult: TUnitAnalysisResult;
begin
  FContext.RegisterUnitExports('First.Unit', ['TShared']);
  FContext.RegisterUnitDependencies('First.Unit', []);
  FContext.RegisterUnitExports('Second.Unit', ['TShared']);
  FContext.RegisterUnitDependencies('Second.Unit', []);
  LSyntaxTree := TMockSyntaxTree.Create;
  LSyntaxTree.UnitName := 'Consumer.Unit';
  LSyntaxTree.IntfUses := ['Second.Unit', 'First.Unit'];
  LSyntaxTree.IntfIdents := ['First.Unit.TShared'];
  LResult := FAnalyzer.Execute(LSyntaxTree, FContext);
  Assert.AreEqual(1, Integer(Length(LResult.UnusedUnits)));
  Assert.AreEqual('Second.Unit', LResult.UnusedUnits[0]);
  Assert.AreEqual(0, Integer(Length(LResult.PreservedAmbiguities)));
end;

procedure TDomainTests.UniqueIdentifierDoesNotPreserveUnrelatedUnit;
var
  LSyntaxTree: TMockSyntaxTree;
  LResult: TUnitAnalysisResult;
begin
  FContext.RegisterUnitExports('Used.Unit', ['TUnique']);
  FContext.RegisterUnitDependencies('Used.Unit', []);
  FContext.RegisterUnitExports('Unused.Unit', ['TOther']);
  FContext.RegisterUnitDependencies('Unused.Unit', []);
  LSyntaxTree := TMockSyntaxTree.Create;
  LSyntaxTree.UnitName := 'Consumer.Unit';
  LSyntaxTree.IntfUses := ['Used.Unit', 'Unused.Unit'];
  LSyntaxTree.IntfIdents := ['TUnique'];
  LResult := FAnalyzer.Execute(LSyntaxTree, FContext);
  Assert.AreEqual(1, Integer(Length(LResult.UnusedUnits)));
  Assert.AreEqual('Unused.Unit', LResult.UnusedUnits[0]);
  Assert.AreEqual(0, Integer(Length(LResult.PreservedAmbiguities)));
end;

initialization
  TDUnitX.RegisterTestFixture(TDomainTests);

end.


