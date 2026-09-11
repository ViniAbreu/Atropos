unit Atropos.Tests.FileSystem;

interface
uses
  Atropos.Core.Ports, Atropos.Adapters.FileSystem, DUnitX.TestFramework,
  System.SysUtils, System.IOUtils, System.Classes;

type
  [TestFixture]
  TFileSystemTests = class
  private
    FFileService: IFileService;
    FTestFile: string;
    function GetBackupPath(const AFilePath: string): string;
    function GetManifestPath: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    
    [Test]
    [TestCase('Create backup file', 'Should create a .bak backup file before modifying')]
    procedure Test_BackupFile_CreatesBakFile;
    [Test]
    [TestCase('Read and write content', 'Should accurately read and write file contents')]
    procedure Test_ReadWriteContent;
    [Test]
    procedure ExistingUserBackupIsPreserved;
    [Test]
    procedure RepeatedBackupKeepsOriginalContent;
    [Test]
    procedure UTF8WithoutBOMIsPreserved;
    [Test]
    procedure CommitDeletesCreatedBackup;
    [Test]
    procedure MissingFileOperationsRaiseExceptions;
    [Test]
    procedure EnsureDirectoryCreatesNestedPath;
    [Test]
    procedure RecoversBackupLeftByInterruptedExecution;
    [Test]
    procedure ConcurrentTransactionInSameProjectIsRejected;
    [Test]
    procedure BackupCreatesVersionedHashedManifest;
    [Test]
    procedure LegacyBackupWithoutManifestIsPreservedAndRejected;
    [Test]
    procedure TamperedBackupIsPreservedAndNotRestored;
    [Test]
    procedure MissingOriginalIsRecoveredFromVerifiedBackup;
    [Test]
    procedure CommittedManifestCleansBackupsWithoutRollback;
    [Test]
    procedure MissingBackupWithUnchangedOriginalCompletesRecovery;
    [Test]
    procedure InvalidManifestIsPreservedAndRejected;
    [Test]
    procedure MissingBackupWithChangedOriginalBlocksRecovery;
    [Test]
    procedure PartiallyCompletedRollbackResumesSafely;
    [Test]
    procedure ManifestWithMismatchedBackupPathIsRejectedBeforeRestore;
    [Test] procedure LockedLegacyTemporaryFileDoesNotBlockTransaction;
  end;

implementation

function TFileSystemTests.GetBackupPath(const AFilePath: string): string;
var
  LBackups: TArray<string>;
begin
  LBackups := TDirectory.GetFiles(TPath.GetDirectoryName(AFilePath),
    TPath.GetFileName(AFilePath) + '.atropos-*.bak');
  Assert.AreEqual(1, Integer(Length(LBackups)));
  Result := LBackups[0];
end;

function TFileSystemTests.GetManifestPath: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(FTestFile),
    '.atropos-transaction.json');
end;

procedure TFileSystemTests.Setup;
var
  LTestDirectory: string;
begin
  FFileService := TFileSystemAdapter.Create;
  LTestDirectory := TPath.Combine(TPath.GetTempPath,
    'Atropos-' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(LTestDirectory);
  FTestFile := TPath.Combine(LTestDirectory, 'Sample.pas');
  TFile.WriteAllText(FTestFile, 'initial content', TEncoding.UTF8);
end;

procedure TFileSystemTests.ExistingUserBackupIsPreserved;
var
  LUserBackupPath: string;
begin
  LUserBackupPath := FTestFile + '.bak';
  TFile.WriteAllText(LUserBackupPath, 'user backup', TEncoding.UTF8);
  FFileService.BackupFile(FTestFile);
  FFileService.WriteFileContent(FTestFile, 'changed content');
  FFileService.RestoreBackups;

  Assert.AreEqual('initial content', FFileService.ReadFileContent(FTestFile));
  Assert.AreEqual('user backup', TFile.ReadAllText(LUserBackupPath, TEncoding.UTF8));
end;

procedure TFileSystemTests.RepeatedBackupKeepsOriginalContent;
begin
  FFileService.BackupFile(FTestFile);
  FFileService.WriteFileContent(FTestFile, 'first change');
  FFileService.BackupFile(FTestFile);
  FFileService.WriteFileContent(FTestFile, 'second change');
  FFileService.RestoreBackups;

  Assert.AreEqual('initial content', FFileService.ReadFileContent(FTestFile));
end;

procedure TFileSystemTests.UTF8WithoutBOMIsPreserved;
var
  LContent: string;
  LWrittenBytes: TBytes;
begin
  TFile.WriteAllBytes(FTestFile, TEncoding.UTF8.GetBytes('ação original'));

  LContent := FFileService.ReadFileContent(FTestFile);
  Assert.AreEqual('ação original', LContent);
  FFileService.WriteFileContent(FTestFile, 'edição concluída');
  Assert.AreEqual('edição concluída', FFileService.ReadFileContent(FTestFile));
  LWrittenBytes := TFile.ReadAllBytes(FTestFile);
  Assert.IsFalse((Length(LWrittenBytes) >= 3) and (LWrittenBytes[0] = $EF) and
    (LWrittenBytes[1] = $BB) and (LWrittenBytes[2] = $BF));
end;

procedure TFileSystemTests.CommitDeletesCreatedBackup;
var
  LBackupFiles: TArray<string>;
begin
  FFileService.BackupFile(FTestFile);
  LBackupFiles := TDirectory.GetFiles(TPath.GetDirectoryName(FTestFile),
    ExtractFileName(FTestFile) + '.atropos-*.bak');
  Assert.AreEqual(1, Integer(Length(LBackupFiles)));
  FFileService.CommitBackups;
  LBackupFiles := TDirectory.GetFiles(TPath.GetDirectoryName(FTestFile),
    ExtractFileName(FTestFile) + '.atropos-*.bak');
  Assert.AreEqual(0, Integer(Length(LBackupFiles)));
  Assert.IsFalse(TFile.Exists(GetManifestPath));
end;

procedure TFileSystemTests.MissingFileOperationsRaiseExceptions;
var
  LMissingPath: string;
  LBackupRaised: Boolean;
  LReadRaised: Boolean;
begin
  LMissingPath := FTestFile + '.missing';
  LBackupRaised := False;
  try
    FFileService.BackupFile(LMissingPath);
  except
    on E: Exception do
      LBackupRaised := True;
  end;
  LReadRaised := False;
  try
    FFileService.ReadFileContent(LMissingPath);
  except
    on E: Exception do
      LReadRaised := True;
  end;
  Assert.IsTrue(LBackupRaised);
  Assert.IsTrue(LReadRaised);
end;

procedure TFileSystemTests.EnsureDirectoryCreatesNestedPath;
var
  LDirectory: string;
begin
  LDirectory := TPath.Combine(TPath.GetTempPath,
    TGuid.NewGuid.ToString + '\nested\reports');
  try
    FFileService.EnsureDirectory(LDirectory);
    Assert.IsTrue(TDirectory.Exists(LDirectory));
  finally
    TDirectory.Delete(TPath.GetDirectoryName(TPath.GetDirectoryName(LDirectory)), True);
  end;
end;

procedure TFileSystemTests.RecoversBackupLeftByInterruptedExecution;
var
  LInterruptedService: IFileService;
  LRecoveryService: IFileService;
begin
  LInterruptedService := TFileSystemAdapter.Create;
  LInterruptedService.BackupFile(FTestFile);
  LInterruptedService.WriteFileContent(FTestFile, 'interrupted change');

  LRecoveryService := TFileSystemAdapter.Create;
  LRecoveryService.RecoverPendingBackups(TPath.GetDirectoryName(FTestFile));

  Assert.AreEqual('initial content', LRecoveryService.ReadFileContent(FTestFile));
  Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(
    TPath.GetDirectoryName(FTestFile),
    ExtractFileName(FTestFile) + '.atropos-*.bak'))));
end;

procedure TFileSystemTests.ConcurrentTransactionInSameProjectIsRejected;
var
  LFirstService: IFileService;
  LSecondService: IFileService;
  LDirectory: string;
  LRejected: Boolean;
begin
  LDirectory := TPath.GetDirectoryName(FTestFile);
  LFirstService := TFileSystemAdapter.Create;
  LSecondService := TFileSystemAdapter.Create;
  LFirstService.RecoverPendingBackups(LDirectory);
  LRejected := False;
  try
    LSecondService.RecoverPendingBackups(LDirectory);
  except
    on E: Exception do
      LRejected := True;
  end;
  Assert.IsTrue(LRejected);
  LFirstService.CommitBackups;
end;

procedure TFileSystemTests.BackupCreatesVersionedHashedManifest;
var
  LManifestContent: string;
begin
  FFileService.BackupFile(FTestFile);
  Assert.IsTrue(TFile.Exists(GetManifestPath));
  LManifestContent := TFile.ReadAllText(GetManifestPath, TEncoding.UTF8);
  Assert.IsTrue(LManifestContent.Contains('"version":1'));
  Assert.IsTrue(LManifestContent.Contains('"transactionId"'));
  Assert.IsTrue(LManifestContent.Contains('"state":"active"'));
  Assert.IsTrue(LManifestContent.Contains('"createdUtc"'));
  Assert.IsTrue(LManifestContent.Contains('"sha256"'));
  Assert.IsTrue(LManifestContent.Contains(GetBackupPath(FTestFile)
    .Replace('\', '\\')));
end;

procedure TFileSystemTests.LegacyBackupWithoutManifestIsPreservedAndRejected;
var
  LBackupPath: string;
  LRecoveryService: IFileService;
  LRaised: Boolean;
begin
  LBackupPath := FTestFile + '.atropos-' + TGuid.NewGuid.ToString + '.bak';
  TFile.WriteAllText(LBackupPath, 'legacy content', TEncoding.UTF8);
  FFileService.WriteFileContent(FTestFile, 'current content');
  LRecoveryService := TFileSystemAdapter.Create;
  LRaised := False;
  try
    LRecoveryService.RecoverPendingBackups(TPath.GetDirectoryName(FTestFile));
  except
    on E: Exception do
      LRaised := E.Message.Contains('without a transaction manifest');
  end;
  Assert.IsTrue(LRaised);
  Assert.AreEqual('current content', FFileService.ReadFileContent(FTestFile));
  Assert.IsTrue(TFile.Exists(LBackupPath));
end;

procedure TFileSystemTests.TamperedBackupIsPreservedAndNotRestored;
var
  LBackupPath: string;
  LInterruptedService: IFileService;
  LRecoveryService: IFileService;
  LRaised: Boolean;
begin
  LInterruptedService := TFileSystemAdapter.Create;
  LInterruptedService.BackupFile(FTestFile);
  LBackupPath := GetBackupPath(FTestFile);
  TFile.WriteAllText(LBackupPath, 'tampered backup', TEncoding.UTF8);
  LInterruptedService.WriteFileContent(FTestFile, 'changed content');
  LInterruptedService := nil;
  LRecoveryService := TFileSystemAdapter.Create;
  LRaised := False;
  try
    LRecoveryService.RecoverPendingBackups(TPath.GetDirectoryName(FTestFile));
  except
    on E: Exception do
      LRaised := E.Message.Contains('hash mismatch');
  end;
  Assert.IsTrue(LRaised);
  Assert.AreEqual('changed content', FFileService.ReadFileContent(FTestFile));
  Assert.IsTrue(TFile.Exists(LBackupPath));
  Assert.IsTrue(TFile.Exists(GetManifestPath));
end;

procedure TFileSystemTests.MissingOriginalIsRecoveredFromVerifiedBackup;
var
  LInterruptedService: IFileService;
  LRecoveryService: IFileService;
begin
  LInterruptedService := TFileSystemAdapter.Create;
  LInterruptedService.BackupFile(FTestFile);
  TFile.Delete(FTestFile);
  LInterruptedService := nil;
  LRecoveryService := TFileSystemAdapter.Create;
  LRecoveryService.RecoverPendingBackups(TPath.GetDirectoryName(FTestFile));
  Assert.AreEqual('initial content', LRecoveryService.ReadFileContent(FTestFile));
  Assert.IsFalse(TFile.Exists(GetManifestPath));
end;

procedure TFileSystemTests.CommittedManifestCleansBackupsWithoutRollback;
var
  LBackupPath: string;
  LInterruptedService: IFileService;
  LManifestContent: string;
  LRecoveryService: IFileService;
begin
  LInterruptedService := TFileSystemAdapter.Create;
  LInterruptedService.BackupFile(FTestFile);
  LBackupPath := GetBackupPath(FTestFile);
  LInterruptedService.WriteFileContent(FTestFile, 'committed content');
  LManifestContent := TFile.ReadAllText(GetManifestPath, TEncoding.UTF8);
  LManifestContent := LManifestContent.Replace('"state":"active"',
    '"state":"committed"');
  TFile.WriteAllText(GetManifestPath, LManifestContent, TEncoding.UTF8);
  LInterruptedService := nil;
  LRecoveryService := TFileSystemAdapter.Create;
  LRecoveryService.RecoverPendingBackups(TPath.GetDirectoryName(FTestFile));
  Assert.AreEqual('committed content', LRecoveryService.ReadFileContent(FTestFile));
  Assert.IsFalse(TFile.Exists(LBackupPath));
  Assert.IsFalse(TFile.Exists(GetManifestPath));
end;

procedure TFileSystemTests.MissingBackupWithUnchangedOriginalCompletesRecovery;
var
  LBackupPath: string;
  LInterruptedService: IFileService;
  LRecoveryService: IFileService;
begin
  LInterruptedService := TFileSystemAdapter.Create;
  LInterruptedService.BackupFile(FTestFile);
  LBackupPath := GetBackupPath(FTestFile);
  TFile.Delete(LBackupPath);
  LInterruptedService := nil;
  LRecoveryService := TFileSystemAdapter.Create;
  LRecoveryService.RecoverPendingBackups(TPath.GetDirectoryName(FTestFile));
  Assert.AreEqual('initial content', LRecoveryService.ReadFileContent(FTestFile));
  Assert.IsFalse(TFile.Exists(GetManifestPath));
end;

procedure TFileSystemTests.InvalidManifestIsPreservedAndRejected;
var
  LRecoveryService: IFileService;
  LRaised: Boolean;
begin
  TFile.WriteAllText(GetManifestPath, '{invalid json', TEncoding.UTF8);
  LRecoveryService := TFileSystemAdapter.Create;
  LRaised := False;
  try
    LRecoveryService.RecoverPendingBackups(TPath.GetDirectoryName(FTestFile));
  except
    on E: Exception do
      LRaised := E.Message.Contains('JSON object');
  end;
  Assert.IsTrue(LRaised);
  Assert.IsTrue(TFile.Exists(GetManifestPath));
  Assert.AreEqual('initial content', FFileService.ReadFileContent(FTestFile));
end;

procedure TFileSystemTests.MissingBackupWithChangedOriginalBlocksRecovery;
var
  LBackupPath: string;
  LInterruptedService: IFileService;
  LRecoveryService: IFileService;
  LRaised: Boolean;
begin
  LInterruptedService := TFileSystemAdapter.Create;
  LInterruptedService.BackupFile(FTestFile);
  LBackupPath := GetBackupPath(FTestFile);
  TFile.Delete(LBackupPath);
  LInterruptedService.WriteFileContent(FTestFile, 'changed content');
  LInterruptedService := nil;
  LRecoveryService := TFileSystemAdapter.Create;
  LRaised := False;
  try
    LRecoveryService.RecoverPendingBackups(TPath.GetDirectoryName(FTestFile));
  except
    on E: Exception do
      LRaised := E.Message.Contains('backup is missing');
  end;
  Assert.IsTrue(LRaised);
  Assert.AreEqual('changed content', FFileService.ReadFileContent(FTestFile));
  Assert.IsTrue(TFile.Exists(GetManifestPath));
end;

procedure TFileSystemTests.PartiallyCompletedRollbackResumesSafely;
var
  LFirstBackupPath: string;
  LInterruptedService: IFileService;
  LRecoveryService: IFileService;
  LSecondFile: string;
begin
  LSecondFile := TPath.Combine(TPath.GetDirectoryName(FTestFile), 'Second.pas');
  TFile.WriteAllText(LSecondFile, 'second initial', TEncoding.UTF8);
  LInterruptedService := TFileSystemAdapter.Create;
  LInterruptedService.BackupFile(FTestFile);
  LInterruptedService.BackupFile(LSecondFile);
  LFirstBackupPath := GetBackupPath(FTestFile);
  LInterruptedService.WriteFileContent(FTestFile, 'first changed');
  LInterruptedService.WriteFileContent(LSecondFile, 'second changed');
  TFile.Copy(LFirstBackupPath, FTestFile, True);
  TFile.Delete(LFirstBackupPath);
  LInterruptedService := nil;
  LRecoveryService := TFileSystemAdapter.Create;
  LRecoveryService.RecoverPendingBackups(TPath.GetDirectoryName(FTestFile));
  Assert.AreEqual('initial content', LRecoveryService.ReadFileContent(FTestFile));
  Assert.AreEqual('second initial', LRecoveryService.ReadFileContent(LSecondFile));
  Assert.IsFalse(TFile.Exists(GetManifestPath));
end;

procedure TFileSystemTests.ManifestWithMismatchedBackupPathIsRejectedBeforeRestore;
var
  LBackupPath: string;
  LInterruptedService: IFileService;
  LManifestContent: string;
  LRecoveryService: IFileService;
  LRaised: Boolean;
begin
  LInterruptedService := TFileSystemAdapter.Create;
  LInterruptedService.BackupFile(FTestFile);
  LBackupPath := GetBackupPath(FTestFile);
  LInterruptedService.WriteFileContent(FTestFile, 'changed content');
  LManifestContent := TFile.ReadAllText(GetManifestPath, TEncoding.UTF8);
  LManifestContent := LManifestContent.Replace('.bak"', '.invalid"');
  TFile.WriteAllText(GetManifestPath, LManifestContent, TEncoding.UTF8);
  LInterruptedService := nil;
  LRecoveryService := TFileSystemAdapter.Create;
  LRaised := False;
  try
    LRecoveryService.RecoverPendingBackups(TPath.GetDirectoryName(FTestFile));
  except
    on E: Exception do
      LRaised := E.Message.Contains('invalid backup path');
  end;
  Assert.IsTrue(LRaised);
  Assert.AreEqual('changed content', FFileService.ReadFileContent(FTestFile));
  Assert.IsTrue(TFile.Exists(LBackupPath));
end;

procedure TFileSystemTests.TearDown;
begin
  FFileService := nil;
  if TDirectory.Exists(TPath.GetDirectoryName(FTestFile)) then
    TDirectory.Delete(TPath.GetDirectoryName(FTestFile), True);
end;

procedure TFileSystemTests.Test_BackupFile_CreatesBakFile;
var
  LBackupFiles: TArray<string>;
begin
  FFileService.BackupFile(FTestFile);
  LBackupFiles := TDirectory.GetFiles(TPath.GetDirectoryName(FTestFile),
    ExtractFileName(FTestFile) + '.atropos-*.bak');
  Assert.AreEqual(1, Integer(Length(LBackupFiles)), 'Backup file was not created');
  Assert.AreEqual('initial content', TFile.ReadAllText(LBackupFiles[0],
    TEncoding.UTF8), 'Backup content mismatch');
end;

procedure TFileSystemTests.Test_ReadWriteContent;
var
  LContent: string;
begin
  LContent := FFileService.ReadFileContent(FTestFile);
  Assert.AreEqual('initial content', LContent);
  
  FFileService.WriteFileContent(FTestFile, 'new content');
  LContent := FFileService.ReadFileContent(FTestFile);
  Assert.AreEqual('new content', LContent);
end;

procedure TFileSystemTests.LockedLegacyTemporaryFileDoesNotBlockTransaction;
var LLocked: TFileStream; LTemporaryPath: string;
begin
  LTemporaryPath := GetManifestPath + '.tmp';
  LLocked := TFileStream.Create(LTemporaryPath, fmCreate or fmShareExclusive);
  try
    FFileService.BackupFile(FTestFile);
    FFileService.WriteFileContent(FTestFile, 'changed');
    FFileService.RestoreBackups;
    Assert.AreEqual('initial content', FFileService.ReadFileContent(FTestFile));
    Assert.IsFalse(TFile.Exists(GetManifestPath));
    Assert.IsTrue(TFile.Exists(LTemporaryPath), 'Unrelated temporary file must be preserved');
    Assert.AreEqual<NativeInt>(1, Length(TDirectory.GetFiles(
      TPath.GetDirectoryName(FTestFile), '*.tmp')));
  finally
    LLocked.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TFileSystemTests);

end.


