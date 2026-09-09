unit Atropos.Tests.ExecutionLifecycle;

interface

uses
  Atropos.Adapters.ExecutionThread,
  Atropos.Application.ExecutionLifecycle,
  Atropos.Application.ExecutionPresentation,
  DUnitX.TestFramework,
  System.Classes,
  System.SysUtils;

type
  TExecutionCompletionProbe = class
  public
    CompleteCallCount: Integer;
    CompletionThreadId: TThreadID;
    Presentation: TExecutionPresentation;
    procedure Complete;
  end;

  [TestFixture]
  TExecutionLifecycleTests = class
  public
    [Test]
    procedure PreventsConcurrentExecutionAndCloseWhileRunning;
    [Test]
    procedure CompleteAllowsNextExecutionAndClose;
    [Test]
    procedure CancellationIsThreadSafeAndResetsForNextExecution;
    [Test]
    procedure WorkerSynchronizesCompletionAfterSuccessfulWork;
    [Test]
    procedure WorkerSynchronizesCompletionAfterUnhandledFailure;
  end;

implementation

procedure TExecutionCompletionProbe.Complete;
begin
  Inc(CompleteCallCount);
  CompletionThreadId := TThread.CurrentThread.ThreadID;
  if Assigned(Presentation) then
    Presentation.Complete;
end;

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

procedure TExecutionLifecycleTests.CancellationIsThreadSafeAndResetsForNextExecution;
var
  LLifecycle: TExecutionLifecycle;
begin
  LLifecycle := TExecutionLifecycle.Create;
  try
    LLifecycle.TryBegin;
    LLifecycle.RequestCancel;
    Assert.IsTrue(LLifecycle.IsCancellationRequested);
    LLifecycle.Complete;
    Assert.IsTrue(LLifecycle.TryBegin);
    Assert.IsFalse(LLifecycle.IsCancellationRequested);
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

procedure TExecutionLifecycleTests.WorkerSynchronizesCompletionAfterSuccessfulWork;
var
  LCompletion: TExecutionCompletionProbe;
  LThread: TSynchronizedExecutionThread;
begin
  LCompletion := TExecutionCompletionProbe.Create;
  try
    LThread := TSynchronizedExecutionThread.Create(
      procedure
      begin
      end, LCompletion.Complete, False);
    try
      LThread.Start;
      LThread.WaitFor;
      Assert.AreEqual(1, LCompletion.CompleteCallCount);
      Assert.AreEqual(TThread.CurrentThread.ThreadID,
        LCompletion.CompletionThreadId);
    finally
      LThread.Free;
    end;
  finally
    LCompletion.Free;
  end;
end;

procedure TExecutionLifecycleTests.WorkerSynchronizesCompletionAfterUnhandledFailure;
var
  LCompletion: TExecutionCompletionProbe;
  LPresentation: TExecutionPresentation;
  LThread: TSynchronizedExecutionThread;
begin
  LCompletion := TExecutionCompletionProbe.Create;
  LPresentation := TExecutionPresentation.Create;
  try
    Assert.IsTrue(LPresentation.TryBegin);
    Assert.IsFalse(LPresentation.CanClose);
    LCompletion.Presentation := LPresentation;
    LThread := TSynchronizedExecutionThread.Create(
      procedure
      begin
        raise Exception.Create('Expected worker failure');
      end, LCompletion.Complete, False);
    try
      LThread.Start;
      LThread.WaitFor;
      Assert.AreEqual(1, LCompletion.CompleteCallCount);
      Assert.IsTrue(LPresentation.CanClose);
    finally
      LThread.Free;
    end;
  finally
    LPresentation.Free;
    LCompletion.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TExecutionLifecycleTests);

end.
