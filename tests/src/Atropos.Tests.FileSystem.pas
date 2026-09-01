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
  end;

implementation

procedure TFileSystemTests.Setup;
begin
  FFileService := TFileSystemAdapter.Create;
  FTestFile := TPath.Combine(TPath.GetTempPath, 'TestFileSystem.pas');
  TFile.WriteAllText(FTestFile, 'initial content', TEncoding.UTF8);
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


