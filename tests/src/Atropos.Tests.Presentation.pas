unit Atropos.Tests.Presentation;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPresentationTests = class
  public
    [Test] procedure CLIHelpReturnsSuccessAndPrintsUsage;
    [Test] procedure CLIInvalidArgumentsReturnUsageError;
    [Test] procedure CLIProcessEntryRejectsNonProjectInvocation;
    [Test] procedure CLIMissingProjectDoesNotExecute;
    [Test] procedure CLIPropagatesSuccessfulExecutionAndLogs;
    [Test] procedure CLIPropagatesExecutionFailure;
    [Test] procedure CLIConvertsExecutionExceptionToCriticalError;
    [Test] procedure LoggerForwardsAndIgnoresMessagesAsConfigured;
    [Test] procedure PersistentLoggerWritesTimestampedUtf8Messages;
    [Test] procedure DefaultFactoryCreatesApplicationService;
    [Test] procedure ExecutionPresentationTransitionsThroughRunAndCompletion;
    [Test] procedure ExecutionPresentationExposesCancellationState;
    [Test] procedure ExecutionPresentationRejectsConcurrentStart;
    [Test] procedure ExecutionPresentationTracksProgress;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes,
  Atropos.App.CLI,
  Atropos.Adapters.Logger,
  Atropos.Application.AppService,
  Atropos.Application.Factory,
  Atropos.Application.ExecutionPresentation,
  Atropos.Core.Config,
  Atropos.Core.Ports;

procedure TPresentationTests.CLIProcessEntryRejectsNonProjectInvocation;
var LApp: TCLIApp;
begin
  // Exercise ParamStr -> parser -> real console output, without a project.
  // The test runner arguments (or an empty command line) are not a CLI request.
  LApp := TCLIApp.Create;
  try Assert.AreEqual(2,LApp.Run); finally LApp.Free; end;
end;

procedure TPresentationTests.CLIHelpReturnsSuccessAndPrintsUsage;
var
  LOutput: string;
  LExitCode: Integer;
begin
  LExitCode := TCLIApp.RunWith(['--help'],
    procedure(const AMessage: string) begin LOutput := LOutput + AMessage + sLineBreak end,
    function(const APath: string): Boolean begin Result := False end,
    function(const APath: string; const AConfig: TToolConfig;
      const AOnLog: TCLIOutput): Boolean begin Result := False end);
  Assert.AreEqual(0, LExitCode);
  Assert.Contains(LOutput, 'Usage: AtroposCLI');
end;

procedure TPresentationTests.CLIInvalidArgumentsReturnUsageError;
var
  LOutput: string;
begin
  Assert.AreEqual(2, TCLIApp.RunWith([],
    procedure(const AMessage: string) begin LOutput := LOutput + AMessage + sLineBreak end,
    function(const APath: string): Boolean begin Result := False end,
    function(const APath: string; const AConfig: TToolConfig;
      const AOnLog: TCLIOutput): Boolean begin Result := False end));
  Assert.Contains(LOutput, 'Error: The -dproj option is required.');
  Assert.Contains(LOutput, 'Usage: AtroposCLI');
end;

procedure TPresentationTests.CLIMissingProjectDoesNotExecute;
var
  LExecuted: Boolean;
  LOutput: string;
begin
  LExecuted := False;
  Assert.AreEqual(2, TCLIApp.RunWith(['-dproj', 'missing.dproj'],
    procedure(const AMessage: string) begin LOutput := LOutput + AMessage end,
    function(const APath: string): Boolean begin Result := False end,
    function(const APath: string; const AConfig: TToolConfig;
      const AOnLog: TCLIOutput): Boolean begin LExecuted := True; Result := True end));
  Assert.IsFalse(LExecuted);
  Assert.Contains(LOutput, 'Project file not found');
end;

procedure TPresentationTests.CLIPropagatesSuccessfulExecutionAndLogs;
var
  LOutput: string;
begin
  Assert.AreEqual(0, TCLIApp.RunWith(['-dproj', 'project.dproj'],
    procedure(const AMessage: string) begin LOutput := LOutput + AMessage end,
    function(const APath: string): Boolean begin Result := True end,
    function(const APath: string; const AConfig: TToolConfig;
      const AOnLog: TCLIOutput): Boolean begin AOnLog('executed'); Result := True end));
  Assert.AreEqual('executed', LOutput);
end;

procedure TPresentationTests.CLIPropagatesExecutionFailure;
begin
  Assert.AreEqual(1, TCLIApp.RunWith(['-dproj', 'project.dproj'],
    procedure(const AMessage: string) begin end,
    function(const APath: string): Boolean begin Result := True end,
    function(const APath: string; const AConfig: TToolConfig;
      const AOnLog: TCLIOutput): Boolean begin Result := False end));
end;

procedure TPresentationTests.CLIConvertsExecutionExceptionToCriticalError;
var
  LOutput: string;
begin
  Assert.AreEqual(1, TCLIApp.RunWith(['-dproj', 'project.dproj'],
    procedure(const AMessage: string) begin LOutput := LOutput + AMessage end,
    function(const APath: string): Boolean begin Result := True end,
    function(const APath: string; const AConfig: TToolConfig;
      const AOnLog: TCLIOutput): Boolean begin raise Exception.Create('failure') end));
  Assert.Contains(LOutput, 'Critical Error: failure');
end;

procedure TPresentationTests.LoggerForwardsAndIgnoresMessagesAsConfigured;
var
  LMessage: string;
  LLogger: ILogger;
begin
  LLogger := TAppLogger.Create(procedure(const AMessage: string) begin LMessage := AMessage end);
  LLogger.Log('message');
  Assert.AreEqual('message', LMessage);
  LLogger := TAppLogger.Create(nil);
  LLogger.Log('ignored');
  Assert.AreEqual('message', LMessage);
end;

procedure TPresentationTests.PersistentLoggerWritesTimestampedUtf8Messages;
var
  LContent: string;
  LLogPath: string;
  LLogger: ILogger;
begin
  LLogPath := TPath.Combine(TPath.GetTempPath,
    'AtroposLogger-' + TGuid.NewGuid.ToString + '.log');
  try
    LLogger := TAppLogger.CreatePersistent(nil, LLogPath);
    LLogger.Log('Unicode diagnostic: compilação');
    LLogger := nil;
    LContent := TFile.ReadAllText(LLogPath, TEncoding.UTF8);
    Assert.Contains(LContent, 'Unicode diagnostic: compilação');
    Assert.IsTrue(LContent.StartsWith(FormatDateTime('yyyy-mm-dd', Now)));
  finally
    if TFile.Exists(LLogPath) then
      TFile.Delete(LLogPath);
  end;
end;

procedure TPresentationTests.DefaultFactoryCreatesApplicationService;
var
  LService: TProjectCleanerAppService;
begin
  LService := TAppServiceFactory.CreateDefault(TToolConfig.Default);
  try
    Assert.IsNotNull(LService);
  finally
    LService.Free;
  end;
end;

procedure TPresentationTests.ExecutionPresentationTransitionsThroughRunAndCompletion;
var
  LPresentation: TExecutionPresentation;
begin
  LPresentation := TExecutionPresentation.Create;
  try
    Assert.IsTrue(LPresentation.State.ControlsEnabled);
    Assert.IsTrue(LPresentation.TryBegin);
    Assert.IsFalse(LPresentation.State.ControlsEnabled);
    Assert.IsTrue(LPresentation.State.CancelEnabled);
    Assert.IsFalse(LPresentation.CanClose);
    LPresentation.Complete;
    Assert.IsTrue(LPresentation.State.ControlsEnabled);
    Assert.IsFalse(LPresentation.State.CancelEnabled);
    Assert.IsTrue(LPresentation.CanClose);
  finally
    LPresentation.Free;
  end;
end;

procedure TPresentationTests.ExecutionPresentationExposesCancellationState;
var
  LPresentation: TExecutionPresentation;
begin
  LPresentation := TExecutionPresentation.Create;
  try
    LPresentation.RequestCancellation;
    Assert.IsFalse(LPresentation.IsCancellationRequested);
    Assert.IsTrue(LPresentation.TryBegin);
    LPresentation.RequestCancellation;
    Assert.IsTrue(LPresentation.IsCancellationRequested);
    Assert.IsTrue(LPresentation.State.CancellationPending);
    Assert.IsFalse(LPresentation.State.CancelEnabled);
  finally
    LPresentation.Free;
  end;
end;

procedure TPresentationTests.ExecutionPresentationRejectsConcurrentStart;
var
  LPresentation: TExecutionPresentation;
begin
  LPresentation := TExecutionPresentation.Create;
  try
    Assert.IsTrue(LPresentation.TryBegin);
    Assert.IsFalse(LPresentation.TryBegin);
  finally
    LPresentation.Free;
  end;
end;

procedure TPresentationTests.ExecutionPresentationTracksProgress;
var
  LPresentation: TExecutionPresentation;
begin
  LPresentation := TExecutionPresentation.Create;
  try
    LPresentation.UpdateProgress(12, 5);
    Assert.AreEqual(12, LPresentation.State.ProgressMaximum);
    Assert.AreEqual(5, LPresentation.State.ProgressPosition);
    Assert.IsTrue(LPresentation.TryBegin);
    Assert.AreEqual(0, LPresentation.State.ProgressMaximum);
    Assert.AreEqual(0, LPresentation.State.ProgressPosition);
  finally
    LPresentation.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPresentationTests);

end.
