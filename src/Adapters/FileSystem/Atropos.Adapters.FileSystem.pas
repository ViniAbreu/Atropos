unit Atropos.Adapters.FileSystem;

interface
uses
  Atropos.Core.Ports, System.Generics.Collections;

type
  TFileSystemAdapter = class(TInterfacedObject, IFileService)
  private
    FBackupList: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure BackupFile(const AFilePath: string);
    procedure RestoreBackups;
    procedure CommitBackups;
    function ReadFileContent(const AFilePath: string): string;
    procedure WriteFileContent(const AFilePath: string; const AContent: string);
  end;

implementation
uses
  System.SysUtils, System.IOUtils;

constructor TFileSystemAdapter.Create;
begin
  FBackupList := TList<string>.Create;
end;

destructor TFileSystemAdapter.Destroy;
begin
  FBackupList.Free;
  inherited;
end;

procedure TFileSystemAdapter.BackupFile(const AFilePath: string);
var
  LBackupPath: string;
begin
  if not TFile.Exists(AFilePath) then
    raise Exception.CreateFmt('Cannot backup. File does not exist: %s', [AFilePath]);

  LBackupPath := AFilePath + '.bak';
  TFile.Copy(AFilePath, LBackupPath, True);
  if not FBackupList.Contains(AFilePath) then
    FBackupList.Add(AFilePath);
end;

procedure TFileSystemAdapter.RestoreBackups;
var
  LPath, LBackupPath: string;
begin
  for LPath in FBackupList do
  begin
    LBackupPath := LPath + '.bak';
    if TFile.Exists(LBackupPath) then
    begin
      TFile.Copy(LBackupPath, LPath, True);
      TFile.Delete(LBackupPath);
    end;
  end;
  FBackupList.Clear;
end;

procedure TFileSystemAdapter.CommitBackups;
var
  LPath, LBackupPath: string;
begin
  for LPath in FBackupList do
  begin
    LBackupPath := LPath + '.bak';
    if TFile.Exists(LBackupPath) then
      TFile.Delete(LBackupPath);
  end;
  FBackupList.Clear;
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


