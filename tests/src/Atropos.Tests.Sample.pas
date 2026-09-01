unit Atropos.Tests.Sample;

interface
uses
  DUnitX.TestFramework;



type
  [TestFixture]
  TSampleTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    [TestCase('Example test', 'A simple example test')]
    procedure TestExample;
  end;

implementation

procedure TSampleTests.Setup;
begin
end;

procedure TSampleTests.TearDown;
begin
end;

procedure TSampleTests.TestExample;
begin
  Assert.IsTrue(True, 'Este teste deve passar');
end;

initialization
  TDUnitX.RegisterTestFixture(TSampleTests);

end.


