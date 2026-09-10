unit Atropos.Tests.CancellationTransaction;

interface

uses DUnitX.TestFramework, System.SysUtils, Atropos.Core.Ports;

type
  TObservedTransaction = class(TInterfacedObject, IFileService)
  private
    FInner: IFileService;
  public
    WriteCount, RestoreCount, CommitCount: Integer;
    AfterWrite: TProc<string>;
    constructor Create;
    procedure BackupFile(const AFilePath: string);
    procedure RestoreBackups;
    procedure CommitBackups;
    procedure RecoverPendingBackups(const ARootDirectory: string);
    procedure EnsureDirectory(const ADirectory: string);
    function ReadFileContent(const AFilePath: string): string;
    procedure WriteFileContent(const AFilePath, AContent: string);
  end;

  [TestFixture]
  TCancellationTransactionTests = class
  private
    FRoot: string;
    procedure AssertNoTransaction;
    procedure AssertBytes(const APath: string; const AExpected: TBytes);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test]
    [TestCase('Before first write', '0')]
    [TestCase('After first write', '1')]
    [TestCase('After last write', '2')]
    procedure CancellationRestoresRealFiles(const ACancelAfter: Integer);
  end;

implementation

uses System.IOUtils, System.Classes, Atropos.Adapters.FileSystem,
  Atropos.Adapters.DelphiAST, Atropos.Adapters.ExternalUnitResolver,
  Atropos.Application.AppService, Atropos.Core.Config,
  Atropos.Tests.BuildReliability;

constructor TObservedTransaction.Create;
begin
  inherited;
  FInner := TFileSystemAdapter.Create;
end;

procedure TObservedTransaction.BackupFile(const AFilePath: string);
begin
  FInner.BackupFile(AFilePath);
end;

procedure TObservedTransaction.RestoreBackups;
begin
  Inc(RestoreCount);
  FInner.RestoreBackups;
end;

procedure TObservedTransaction.CommitBackups;
begin
  Inc(CommitCount);
  FInner.CommitBackups;
end;

procedure TObservedTransaction.RecoverPendingBackups(const ARootDirectory: string);
begin
  FInner.RecoverPendingBackups(ARootDirectory);
end;

procedure TObservedTransaction.EnsureDirectory(const ADirectory: string);
begin
  FInner.EnsureDirectory(ADirectory);
end;

function TObservedTransaction.ReadFileContent(const AFilePath: string): string;
begin
  Result := FInner.ReadFileContent(AFilePath);
end;

procedure TObservedTransaction.WriteFileContent(const AFilePath, AContent: string);
begin
  FInner.WriteFileContent(AFilePath, AContent);
  Inc(WriteCount);
  if Assigned(AfterWrite) then
    AfterWrite(AFilePath);
end;

procedure TCancellationTransactionTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'Atropos-Cancellation-' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
end;

procedure TCancellationTransactionTests.TearDown;
begin
  if not TPath.GetFullPath(FRoot).StartsWith(
    TPath.Combine(TPath.GetTempPath, 'Atropos-Cancellation-'), True) then
    raise Exception.Create('Refusing cleanup outside cancellation test directory');
  TDirectory.Delete(FRoot, True);
end;

procedure TCancellationTransactionTests.AssertNoTransaction;
begin
  Assert.IsFalse(TFile.Exists(TPath.Combine(FRoot, '.atropos-transaction.json')));
  Assert.AreEqual<NativeInt>(0, Length(TDirectory.GetFiles(FRoot, '*.atropos-*.bak')));
end;

procedure TCancellationTransactionTests.AssertBytes(const APath: string;
  const AExpected: TBytes);
var
  LActual: TBytes;
begin
  LActual := TFile.ReadAllBytes(APath);
  Assert.AreEqual<NativeInt>(Length(AExpected), Length(LActual), APath);
  Assert.IsTrue(CompareMem(@AExpected[0], @LActual[0], Length(AExpected)), APath);
end;

procedure TCancellationTransactionTests.CancellationRestoresRealFiles(const ACancelAfter: Integer);
var
  LFirst, LSecond, LProvider: string;
  LFirstBytes, LSecondBytes, LProviderBytes: TBytes;
  LProject: TProjectParserSpy;
  LParser: IASTParser;
  LFiles: TObservedTransaction;
  LFilesPort, LRecovery: IFileService;
  LBuild: TSuccessfulBuildService;
  LService: TProjectCleanerAppService;
  LConfig: TToolConfig;
  LCancel: Boolean;
begin
  LFirst := TPath.Combine(FRoot, 'First.pas');
  LSecond := TPath.Combine(FRoot, 'Second.pas');
  LProvider := TPath.Combine(FRoot, 'Unused.pas');
  TFile.WriteAllText(LFirst, 'unit First;'#10'interface'#10'uses Unused;'#10 +
    'implementation'#10'// preserved UTF8: ' + Char($00E9) + #10'end.'#10, TEncoding.UTF8);
  TFile.WriteAllText(LSecond, 'unit Second;'#13#10'interface'#13#10'uses Unused;'#13#10 +
    'implementation'#13#10'// preserved UTF16: ' + Char($03A9) + #13#10'end.'#13#10, TEncoding.Unicode);
  TFile.WriteAllText(LProvider, 'unit Unused; interface const Value = 7; implementation end.', TEncoding.UTF8);
  LFirstBytes := TFile.ReadAllBytes(LFirst);
  LSecondBytes := TFile.ReadAllBytes(LSecond);
  LProviderBytes := TFile.ReadAllBytes(LProvider);
  LProject := TProjectParserSpy.Create;
  LProject.Units := [LFirst, LSecond];
  LParser := TDelphiASTAdapter.Create;
  LFiles := TObservedTransaction.Create;
  LFilesPort := LFiles;
  LBuild := TSuccessfulBuildService.Create;
  LConfig := TToolConfig.Default;
  LConfig.RemoveUnused := True;
  LCancel := False;
  LFiles.AfterWrite := procedure(APath: string)
    begin
      Assert.IsTrue(SameText(APath, LFirst) or SameText(APath, LSecond));
      Assert.IsFalse(LFiles.ReadFileContent(APath).Contains('uses Unused;'),
        'Cancellation must follow an actual on-disk edit');
      Assert.IsTrue(TFile.Exists(TPath.Combine(FRoot, '.atropos-transaction.json')));
      Assert.AreEqual<NativeInt>(LFiles.WriteCount,
        Length(TDirectory.GetFiles(FRoot, '*.atropos-*.bak')));
      LCancel := LFiles.WriteCount = ACancelAfter;
    end;
  LService := TProjectCleanerAppService.Create(LProject, LParser, LFilesPort,
    TReportGeneratorStub.Create, TDelphiEnvironmentStub.Create,
    TExternalUnitResolverAdapter.Create(LParser), LBuild, LConfig,
    function: Boolean begin Result := LCancel end);
  try
    LService.OnProgress := procedure(AMax, APosition: Integer)
      begin
        if (ACancelAfter = 0) and (APosition = AMax) then
          LCancel := True;
      end;
    Assert.WillRaise(procedure begin LService.Execute(TPath.Combine(FRoot, 'Test.dproj')) end, EAbort);
    Assert.AreEqual(ACancelAfter, LFiles.WriteCount);
    Assert.AreEqual(1, LFiles.RestoreCount);
    Assert.AreEqual(0, LFiles.CommitCount);
    Assert.AreEqual(1, LBuild.CallCount, 'Cancellation must prevent the final build');
    AssertBytes(LFirst, LFirstBytes);
    AssertBytes(LSecond, LSecondBytes);
    AssertBytes(LProvider, LProviderBytes);
    AssertNoTransaction;
    LRecovery := TFileSystemAdapter.Create;
    LRecovery.RecoverPendingBackups(FRoot);
    LRecovery.BackupFile(LFirst);
    LRecovery.WriteFileContent(LFirst, 'subsequent independent transaction');
    LRecovery.RestoreBackups;
    AssertBytes(LFirst, LFirstBytes);
    AssertBytes(LSecond, LSecondBytes);
    AssertNoTransaction;
  finally
    LService.Free;
    LFiles.AfterWrite := nil;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCancellationTransactionTests);
end.
