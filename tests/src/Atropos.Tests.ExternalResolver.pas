unit Atropos.Tests.ExternalResolver;

interface
uses
  Atropos.Core.Domain, Atropos.Core.Ports, DUnitX.TestFramework;

type
  [TestFixture]
  TExternalResolverTests = class
  private
    FContext: TProjectContext;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    
    [Test]
    [TestCase('Has unit without resolver returns false', 'Should return false when checking for a unit without a resolver')]
    procedure TestHasUnit_WithoutResolver_ReturnsFalse;
    
    [Test]
    [TestCase('Has unit with resolver found', 'Should return true and cache when unit is found using resolver')]
    procedure TestHasUnit_WithResolver_Found_ReturnsTrueAndCaches;
    
    [Test]
    [TestCase('Has unit with resolver not found', 'Should return false and cache when unit is not found using resolver')]
    procedure TestHasUnit_WithResolver_NotFound_ReturnsFalseAndCaches;
  end;

  TMockExternalResolver = class(TInterfacedObject, IExternalUnitResolver)
  public
    CallCount: Integer;
    procedure Initialize(const ASearchPaths: TArray<string>; const ADelphiPath, ABasePath: string);
    function TryResolveUnit(const AUnitName: string; out AExports: TArray<string>; out AHasInit: Boolean): Boolean;
  end;

implementation

{ TMockExternalResolver }

procedure TMockExternalResolver.Initialize(const ASearchPaths: TArray<string>; const ADelphiPath, ABasePath: string);
begin
  // Do nothing in mock
end;

function TMockExternalResolver.TryResolveUnit(const AUnitName: string; out AExports: TArray<string>; out AHasInit: Boolean): Boolean;
begin
  Inc(CallCount);
  AHasInit := False;
  if AUnitName = 'SysUtils' then
  begin
    AExports := ['ExtractFilePath', 'FileExists'];
    Result := True;
  end
  else
  begin
    AExports := [];
    Result := False;
  end;
end;

{ TExternalResolverTests }

procedure TExternalResolverTests.Setup;
begin
  FContext := nil;
end;

procedure TExternalResolverTests.TearDown;
begin
  if Assigned(FContext) then
    FContext.Free;
end;

procedure TExternalResolverTests.TestHasUnit_WithoutResolver_ReturnsFalse;
begin
  FContext := TProjectContext.Create(nil);
  Assert.IsFalse(FContext.HasUnit('SysUtils'));
end;

procedure TExternalResolverTests.TestHasUnit_WithResolver_Found_ReturnsTrueAndCaches;
var
  LResolver: TMockExternalResolver;
begin
  LResolver := TMockExternalResolver.Create;
  FContext := TProjectContext.Create(LResolver);
  
  // First call should resolve
  Assert.IsTrue(FContext.HasUnit('SysUtils'));
  Assert.AreEqual(1, LResolver.CallCount);
  
  // It should register the exports
  Assert.IsTrue(FContext.UnitExportsIdentifier('SysUtils', 'FileExists'));
  
  // Second call should hit the cache and not call resolver again
  Assert.IsTrue(FContext.HasUnit('SysUtils'));
  Assert.AreEqual(1, LResolver.CallCount);
end;

procedure TExternalResolverTests.TestHasUnit_WithResolver_NotFound_ReturnsFalseAndCaches;
var
  LResolver: TMockExternalResolver;
begin
  LResolver := TMockExternalResolver.Create;
  FContext := TProjectContext.Create(LResolver);
  
  // First call should fail to resolve
  Assert.IsFalse(FContext.HasUnit('UnknownUnit'));
  Assert.AreEqual(1, LResolver.CallCount);
  
  // Second call should hit the cache (MissingUnits) and not call resolver
  Assert.IsFalse(FContext.HasUnit('UnknownUnit'));
  Assert.AreEqual(1, LResolver.CallCount);
end;

initialization
  TDUnitX.RegisterTestFixture(TExternalResolverTests);

end.

