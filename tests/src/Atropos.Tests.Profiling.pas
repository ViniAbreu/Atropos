unit Atropos.Tests.Profiling;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TProfilingTests = class
  public
    [Test] procedure DisabledMeasurementIsEmpty;
    [Test] procedure NestedTimesAreExclusiveAndCallsAccumulate;
    [Test] procedure ExceptionsCloseScopes;
    [Test] procedure ActiveScopesRejectPrematureAccess;
    [Test] procedure ActivationIsThreadLocal;
  end;
implementation
uses System.SysUtils, System.Classes, Atropos.Core.Profiling;

procedure RaiseWithinProfile;
var LScope: IInterface;
begin
  LScope := TExecutionProfile.Measure('failure');
  raise EAbort.Create('expected');
end;

procedure TProfilingTests.DisabledMeasurementIsEmpty;
begin
  Assert.IsNull(TExecutionProfile.Measure('disabled'));
end;

procedure TProfilingTests.NestedTimesAreExclusiveAndCallsAccumulate;
var LProfile: TExecutionProfile; LTick: Int64; LOuter, LInner: IInterface;
  LSamples: TArray<TProfileSample>;
begin
  LTick := 0;
  LProfile := TExecutionProfile.Create(function: Int64 begin Result := LTick end);
  try
    LProfile.Activate;
    LOuter := TExecutionProfile.Measure('decision');
    LTick := 10;
    LInner := TExecutionProfile.Measure('parse', 'A.pas');
    LTick := 30;
    LInner := nil;
    LTick := 40;
    LInner := TExecutionProfile.Measure('parse', 'A.pas');
    LTick := 50;
    LInner := nil;
    LTick := 100;
    LOuter := nil;
    LProfile.Deactivate;
    LSamples := LProfile.Samples;
    Assert.AreEqual<NativeInt>(2, Length(LSamples));
    Assert.AreEqual<Int64>(100, LSamples[0].InclusiveTicks);
    Assert.AreEqual<Int64>(70, LSamples[0].ExclusiveTicks);
    Assert.AreEqual<Int64>(2, LSamples[1].Calls);
    Assert.AreEqual<Int64>(30, LSamples[1].ExclusiveTicks);
    Assert.AreEqual('A.pas', LSamples[1].Subject);
  finally
    LInner := nil;
    LOuter := nil;
    LProfile.Free;
  end;
end;

procedure TProfilingTests.ExceptionsCloseScopes;
var LProfile: TExecutionProfile; LSamples: TArray<TProfileSample>;
begin
  LProfile := TExecutionProfile.Create;
  try
    LProfile.Activate;
    Assert.WillRaise(RaiseWithinProfile, EAbort);
    LProfile.Deactivate;
    LSamples := LProfile.Samples;
    Assert.AreEqual<NativeInt>(1, Length(LSamples));
    Assert.AreEqual<Int64>(1, LSamples[0].Calls);
    Assert.IsTrue(LSamples[0].InclusiveTicks >= 0);
  finally
    LProfile.Free;
  end;
end;
procedure TProfilingTests.ActiveScopesRejectPrematureAccess;
var LProfile, LSecond: TExecutionProfile; LScope: IInterface;
begin
  LProfile := TExecutionProfile.Create;
  LSecond := TExecutionProfile.Create;
  try
    LProfile.Activate;
    Assert.WillRaise(procedure begin LSecond.Activate end, EInvalidOperation);
    LScope := TExecutionProfile.Measure('active');
    Assert.WillRaise(procedure begin LProfile.Deactivate end, EInvalidOperation);
    Assert.WillRaise(procedure begin LProfile.Samples end, EInvalidOperation);
    LScope := nil;
    LProfile.Deactivate;
  finally
    LScope := nil;
    LSecond.Free;
    LProfile.Free;
  end;
end;

procedure TProfilingTests.ActivationIsThreadLocal;
var LProfile: TExecutionProfile; LThread: TThread; LDisabled: Boolean;
begin
  LDisabled := False;
  LProfile := TExecutionProfile.Create;
  try
    LProfile.Activate;
    LThread := TThread.CreateAnonymousThread(procedure
      begin LDisabled := not Assigned(TExecutionProfile.Measure('other-thread')) end);
    LThread.FreeOnTerminate := False;
    try
      LThread.Start;
      LThread.WaitFor;
      Assert.IsTrue(LDisabled);
    finally
      LThread.Free;
    end;
    LProfile.Deactivate;
  finally
    LProfile.Free;
  end;
end;
initialization
  TDUnitX.RegisterTestFixture(TProfilingTests);
end.
