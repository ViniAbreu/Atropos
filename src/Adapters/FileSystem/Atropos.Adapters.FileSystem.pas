unit Atropos.Adapters.FileSystem;

interface
uses
  Atropos.Core.Ports;

type
  TFileSystemAdapter = class(TInterfacedObject, IFileService)
  public
    procedure BackupFile(const AFilePath: string);
    function ReadFileContent(const AFilePath: string): string;
    procedure WriteFileContent(const AFilePath: string; const AContent: string);
  end;

implementation
uses
  System.SysUtils, System.IOUtils;



procedure TFileSystemAdapter.BackupFile(const AFilePath: string);
var
  LBackupPath: string;
begin
  if not TFile.Exists(AFilePath) then
    raise Exception.CreateFmt('Cannot backup. File does not exist: %s', [AFilePath]);

  LBackupPath := AFilePath + '.bak';
  TFile.Copy(AFilePath, LBackupPath, True);
end;

function TFileSystemAdapter.ReadFileContent(const AFilePath: string): string;
begin
  if not TFile.Exists(AFilePath) then
    raise Exception.CreateFmt('Cannot read. File does not exist: %s', [AFilePath]);

  Result := TFile.ReadAllText(AFilePath);
end;

procedure TFileSystemAdapter.WriteFileContent(const AFilePath, AContent: string);
var
  LEncoding: TEncoding;
begin
  LEncoding := nil;
  if TFile.Exists(AFilePath) then
  begin
    var LBytes := TFile.ReadAllBytes(AFilePath);
    TEncoding.GetBufferEncoding(LBytes, LEncoding);
  end;

  if LEncoding = nil then
    LEncoding := TEncoding.Default;

  TFile.WriteAllText(AFilePath, AContent, LEncoding);
end;

end.


