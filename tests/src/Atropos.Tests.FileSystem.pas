unit Atropos.Tests.FileSystem;

interface
uses
  Atropos.Core.Ports, Atropos.Adapters.FileSystem, DUnitX.TestFramework, System.SysUtils, System.IOUtils;

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
  end;

implementation

procedure TFileSystemTests.Setup;
begin
  FFileService := TFileSystemAdapter.Create;
  FTestFile := TPath.Combine(TPath.GetTempPath, 'Atropos-' + TGuid.NewGuid.ToString + '.pas');
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
  LUTF8WithoutBOM: TUTF8Encoding;
  LContent: string;
  LWrittenBytes: TBytes;
begin
  LUTF8WithoutBOM := TUTF8Encoding.Create(False);
  try
    TFile.WriteAllBytes(FTestFile, LUTF8WithoutBOM.GetBytes('ação original'));
  finally
    LUTF8WithoutBOM.Free;
  end;

  LContent := FFileService.ReadFileContent(FTestFile);
  Assert.AreEqual('ação original', LContent);
  FFileService.WriteFileContent(FTestFile, 'edição concluída');
  Assert.AreEqual('edição concluída', FFileService.ReadFileContent(FTestFile));
  LWrittenBytes := TFile.ReadAllBytes(FTestFile);
  Assert.IsFalse((Length(LWrittenBytes) >= 3) and (LWrittenBytes[0] = $EF) and
    (LWrittenBytes[1] = $BB) and (LWrittenBytes[2] = $BF));
end;

procedure TFileSystemTests.TearDown;
begin
  if TFile.Exists(FTestFile) then
    TFile.Delete(FTestFile);
  if TFile.Exists(FTestFile + '.bak') then
    TFile.Delete(FTestFile + '.bak');
end;

procedure TFileSystemTests.Test_BackupFile_CreatesBakFile;
var
  LBakFile: string;
begin
  LBakFile := FTestFile + '.bak';
  
  if TFile.Exists(LBakFile) then
    TFile.Delete(LBakFile);
    
  FFileService.BackupFile(FTestFile);
  
  Assert.IsTrue(TFile.Exists(LBakFile), 'Backup file was not created');
  Assert.AreEqual('initial content', TFile.ReadAllText(LBakFile, TEncoding.UTF8), 'Backup content mismatch');
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


