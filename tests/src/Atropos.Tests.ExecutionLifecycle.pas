unit Atropos.Tests.ExecutionLifecycle;

interface

uses
  Atropos.Application.ExecutionLifecycle,
  DUnitX.TestFramework;

type
  [TestFixture]
  TExecutionLifecycleTests = class
  public
    [Test]
    procedure PreventsConcurrentExecutionAndCloseWhileRunning;
    [Test]
    procedure CompleteAllowsNextExecutionAndClose;
  end;

implementation

procedure TExecutionLifecycleTests.PreventsConcurrentExecutionAndCloseWhileRunning;
var
  LLifecycle: TExecutionLifecycle;
begin
  LLifecycle := TExecutionLifecycle.Create;
  try
    Assert.IsTrue(LLifecycle.TryBegin);
    Assert.IsTrue(LLifecycle.Running);
    Assert.IsFalse(LLifecycle.TryBegin);
    Assert.IsFalse(LLifecycle.CanClose);
  finally
    LLifecycle.Free;
  end;
end;

procedure TExecutionLifecycleTests.CompleteAllowsNextExecutionAndClose;
var
  LLifecycle: TExecutionLifecycle;
begin
  LLifecycle := TExecutionLifecycle.Create;
  try
    LLifecycle.TryBegin;
    LLifecycle.Complete;
    Assert.IsFalse(LLifecycle.Running);
    Assert.IsTrue(LLifecycle.CanClose);
    Assert.IsTrue(LLifecycle.TryBegin);
  finally
    LLifecycle.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TExecutionLifecycleTests);

end.
