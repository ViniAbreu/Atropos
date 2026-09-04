unit Atropos.Tests.ExecutionConfig;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TExecutionConfigTests = class
  public
    [Test]
    procedure SelectedOptionsAreCopiedToConfiguration;
    [Test]
    procedure UnselectedOptionsRemainDisabled;
  end;

implementation

uses
  Atropos.Application.ExecutionConfig,
  Atropos.Core.Config;

procedure TExecutionConfigTests.SelectedOptionsAreCopiedToConfiguration;
var
  LConfig: TToolConfig;
begin
  LConfig := TExecutionConfigFactory.FromSelections(True, True, True);
  Assert.IsTrue(LConfig.RemoveUnused);
  Assert.IsTrue(LConfig.MoveToImplementation);
  Assert.IsTrue(LConfig.EnableDebug);
end;

procedure TExecutionConfigTests.UnselectedOptionsRemainDisabled;
var
  LConfig: TToolConfig;
begin
  LConfig := TExecutionConfigFactory.FromSelections(False, False, False);
  Assert.IsFalse(LConfig.RemoveUnused);
  Assert.IsFalse(LConfig.MoveToImplementation);
  Assert.IsFalse(LConfig.EnableDebug);
  Assert.IsFalse(LConfig.ExportHTML);
  Assert.IsFalse(LConfig.ExportTXT);
end;

initialization
  TDUnitX.RegisterTestFixture(TExecutionConfigTests);

end.
