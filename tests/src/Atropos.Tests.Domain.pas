unit Atropos.Tests.Domain;

interface
uses
  Atropos.Core.Ports, Atropos.Core.Domain, DUnitX.TestFramework;

type
  { Mock AST }
  TMockSyntaxTree = class(TInterfacedObject, IUnitSyntaxTree)
  public
    UnitName: string;
    IntfUses: TArray<string>;
    ImplUses: TArray<string>;
    IntfIdents: TArray<string>;
    ImplIdents: TArray<string>;
    
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
    procedure InitializationUnitsArePreservedUnlessNative;
  end;

implementation

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
  FContext.RegisterUnitExports('System.Classes', ['TStringList', 'TComponent']);
  FContext.RegisterUnitExports('Vcl.Forms', ['TForm']);

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
  Assert.AreEqual(1, Length(LResult.UnitsToMoveToImpl));
  Assert.AreEqual('Vcl.Forms', LResult.UnitsToMoveToImpl[0]);
  
  // Nenhuma foi "completamente não usada" neste cenário, oh wait, TForm was used.
  // Vamos adicionar uma não usada:
  FContext.RegisterUnitExports('UnusedUnit', ['SomeDummyExport']);
  LMockTreeObj.IntfUses := ['System.SysUtils', 'System.Classes', 'Vcl.Forms', 'UnusedUnit'];
  LResult := FAnalyzer.Execute(LMockTree, FContext);
  
  Assert.AreEqual(1, Length(LResult.UnusedUnits));
  Assert.AreEqual('UnusedUnit', LResult.UnusedUnits[0]);
end;

procedure TDomainTests.HelpersAndQualifiedIdentifiersAreResolved;
begin
  FContext.RegisterUnitExports('Helper.Unit', [
    '!HELPER:ToText:string',
    'TArray']);

  Assert.IsTrue(FContext.UnitExportsIdentifier('Helper.Unit', 'ToText', ['string']));
  Assert.IsTrue(FContext.UnitExportsIdentifier('Helper.Unit', 'System.TArray<string>', []));
  Assert.IsFalse(FContext.UnitExportsIdentifier('Helper.Unit', 'UnknownIdentifier', []));
end;

procedure TDomainTests.InitializationUnitsArePreservedUnlessNative;
begin
  FContext.RegisterUnitExports('SideEffect.Unit', [], True, False);
  FContext.RegisterUnitExports('Native.Unit', [], True, True);

  Assert.IsTrue(FContext.UnitHasInitialization('SideEffect.Unit'));
  Assert.IsFalse(FContext.UnitHasInitialization('Native.Unit'));
  Assert.IsFalse(FContext.UnitHasInitialization('Missing.Unit'));
end;

initialization
  TDUnitX.RegisterTestFixture(TDomainTests);

end.


