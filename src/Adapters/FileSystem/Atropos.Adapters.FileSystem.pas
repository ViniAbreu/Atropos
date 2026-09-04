unit Atropos.Adapters.FileSystem;

interface
uses
  Atropos.Core.Ports,
  System.Generics.Collections,
  System.SysUtils;

type
  TFileSystemAdapter = class(TInterfacedObject, IFileService)
  private
    FBackupPaths: TDictionary<string, string>;
    function DetectEncoding(const ABytes: TBytes): TEncoding;
    function IsValidUTF8(const ABytes: TBytes): Boolean;
    function CreateBackupPath(const AFilePath: string): string;
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
uses System.IOUtils;

constructor TFileSystemAdapter.Create;
begin
  FBackupPaths := TDictionary<string, string>.Create;
end;

destructor TFileSystemAdapter.Destroy;
begin
  FBackupPaths.Free;
  inherited;
end;

procedure TFileSystemAdapter.BackupFile(const AFilePath: string);
var
  LBackupPath: string;
begin
  if not TFile.Exists(AFilePath) then
    raise Exception.CreateFmt('Cannot backup. File does not exist: %s', [AFilePath]);

  if FBackupPaths.ContainsKey(AFilePath) then
    Exit;

  LBackupPath := CreateBackupPath(AFilePath);
  TFile.Copy(AFilePath, LBackupPath, True);
  FBackupPaths.Add(AFilePath, LBackupPath);
end;

function TFileSystemAdapter.CreateBackupPath(const AFilePath: string): string;
begin
  Result := AFilePath + '.bak';
  if not TFile.Exists(Result) then
    Exit;

  Result := AFilePath + '.atropos-' + TGuid.NewGuid.ToString + '.bak';
end;

procedure TFileSystemAdapter.RestoreBackups;
var
  LBackup: TPair<string, string>;
begin
  for LBackup in FBackupPaths do
  begin
    if not TFile.Exists(LBackup.Value) then
      Continue;

    TFile.Copy(LBackup.Value, LBackup.Key, True);
    TFile.Delete(LBackup.Value);
  end;
  FBackupPaths.Clear;
end;

procedure TFileSystemAdapter.CommitBackups;
var
  LBackup: TPair<string, string>;
begin
  for LBackup in FBackupPaths do
  begin
    if TFile.Exists(LBackup.Value) then
      TFile.Delete(LBackup.Value);
  end;
  FBackupPaths.Clear;
end;

function TFileSystemAdapter.DetectEncoding(const ABytes: TBytes): TEncoding;
var
  LDetectedEncoding: TEncoding;
begin
  LDetectedEncoding := nil;
  if TEncoding.GetBufferEncoding(ABytes, LDetectedEncoding) > 0 then
    Exit(LDetectedEncoding);

  Result := TEncoding.Default;
  if IsValidUTF8(ABytes) then
    Result := TEncoding.UTF8;
end;

function TFileSystemAdapter.IsValidUTF8(const ABytes: TBytes): Boolean;
var
  LIndex: Integer;
  LContinuationCount: Integer;
  LContinuationIndex: Integer;
begin
  Result := False;
  LIndex := 0;
  while LIndex < Length(ABytes) do
  begin
    if ABytes[LIndex] <= $7F then
    begin
      Inc(LIndex);
      Continue;
    end;

    LContinuationCount := 0;
    if (ABytes[LIndex] >= $C2) and (ABytes[LIndex] <= $DF) then
      LContinuationCount := 1;
    if (ABytes[LIndex] >= $E0) and (ABytes[LIndex] <= $EF) then
      LContinuationCount := 2;
    if (ABytes[LIndex] >= $F0) and (ABytes[LIndex] <= $F4) then
      LContinuationCount := 3;
    if LContinuationCount = 0 then
      Exit;
    if LIndex + LContinuationCount >= Length(ABytes) then
      Exit;

    for LContinuationIndex := 1 to LContinuationCount do
      if (ABytes[LIndex + LContinuationIndex] < $80) or (ABytes[LIndex + LContinuationIndex] > $BF) then
        Exit;

    if (ABytes[LIndex] = $E0) and (ABytes[LIndex + 1] < $A0) then
      Exit;
    if (ABytes[LIndex] = $ED) and (ABytes[LIndex + 1] > $9F) then
      Exit;
    if (ABytes[LIndex] = $F0) and (ABytes[LIndex + 1] < $90) then
      Exit;
    if (ABytes[LIndex] = $F4) and (ABytes[LIndex + 1] > $8F) then
      Exit;

    Inc(LIndex, LContinuationCount + 1);
  end;
  Result := True;
end;

function TFileSystemAdapter.ReadFileContent(const AFilePath: string): string;
begin
  if not TFile.Exists(AFilePath) then
    raise Exception.CreateFmt('Cannot read. File does not exist: %s', [AFilePath]);

  Result := TFile.ReadAllText(AFilePath, DetectEncoding(TFile.ReadAllBytes(AFilePath)));
end;

procedure TFileSystemAdapter.WriteFileContent(const AFilePath, AContent: string);
var
  LEncoding: TEncoding;
  LBytes: TBytes;
begin
  if not TFile.Exists(AFilePath) then
  begin
    TFile.WriteAllText(AFilePath, AContent, TEncoding.Default);
    Exit;
  end;

  LBytes := TFile.ReadAllBytes(AFilePath);
  LEncoding := nil;
  if TEncoding.GetBufferEncoding(LBytes, LEncoding) > 0 then
  begin
    TFile.WriteAllText(AFilePath, AContent, LEncoding);
    Exit;
  end;

  if IsValidUTF8(LBytes) then
  begin
    TFile.WriteAllBytes(AFilePath, TEncoding.UTF8.GetBytes(AContent));
    Exit;
  end;

  TFile.WriteAllText(AFilePath, AContent, TEncoding.Default);
end;

end.
