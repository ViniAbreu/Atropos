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
  end;

implementation

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

initialization
  TDUnitX.RegisterTestFixture(TFileSystemTests);

end.


