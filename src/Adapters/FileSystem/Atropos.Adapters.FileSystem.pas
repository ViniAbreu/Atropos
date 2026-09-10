unit Atropos.Adapters.FileSystem;

interface
uses
  Atropos.Adapters.FileTransaction,
  Atropos.Core.Ports,
  System.Classes,
  System.SysUtils;

type
  TFileSystemAdapter = class(TInterfacedObject, IFileService)
  private
    FManifest: TFileTransactionManifest;
    FTransactionRoot: string;
    FTransactionLock: TFileStream;
    FLockPath: string;
    function CreateBackupPath(const AFilePath: string): string;
    function GetManifestPath: string;
    function IsExpectedBackupPath(const AOriginalPath, ABackupPath,
      ATransactionId: string): Boolean;
    procedure CleanupCommittedTransaction(
      AManifest: TFileTransactionManifest);
    procedure EnsureManifest(const AFilePath: string);
    procedure RejectLegacyBackups(const ARootDirectory: string);
    procedure RestoreManifest(AManifest: TFileTransactionManifest);
    procedure RestoreManifestEntry(const AEntry: TFileTransactionEntry;
      const ATransactionId: string);
    procedure ValidateManifestEntry(const AEntry: TFileTransactionEntry;
      const ATransactionId: string);
    procedure ReleaseTransactionLock;
  public
    constructor Create;
    destructor Destroy; override;
    procedure BackupFile(const AFilePath: string);
    procedure RestoreBackups;
    procedure CommitBackups;
    procedure RecoverPendingBackups(const ARootDirectory: string);
    procedure EnsureDirectory(const ADirectory: string);
    function ReadFileContent(const AFilePath: string): string;
    procedure WriteFileContent(const AFilePath: string; const AContent: string);
  end;

implementation
uses System.IOUtils, Atropos.Adapters.SourceEncoding;

constructor TFileSystemAdapter.Create;
begin
end;

procedure TFileSystemAdapter.EnsureDirectory(const ADirectory: string);
begin
  if ADirectory.IsEmpty then
    Exit;
  TDirectory.CreateDirectory(ADirectory);
end;

destructor TFileSystemAdapter.Destroy;
begin
  ReleaseTransactionLock;
  FManifest.Free;
  inherited;
end;

procedure TFileSystemAdapter.BackupFile(const AFilePath: string);
var
  LBackupPath: string;
  LEntry: TFileTransactionEntry;
  LOriginalPath: string;
begin
  if not TFile.Exists(AFilePath) then
    raise Exception.CreateFmt('Cannot backup. File does not exist: %s', [AFilePath]);

  EnsureManifest(AFilePath);
  LOriginalPath := TPath.GetFullPath(AFilePath);
  if FManifest.HasOriginal(LOriginalPath) then
    Exit;

  LBackupPath := CreateBackupPath(LOriginalPath);
  LEntry.OriginalPath := LOriginalPath;
  LEntry.BackupPath := LBackupPath;
  LEntry.OriginalHash := TFileTransactionManifest.HashFile(LOriginalPath);
  FManifest.AddEntry(LEntry);
  FManifest.Save;
  TFile.Copy(LOriginalPath, LBackupPath, True);
  if not SameText(TFileTransactionManifest.HashFile(LBackupPath),
    LEntry.OriginalHash) then
    raise Exception.CreateFmt('Backup verification failed: %s', [LBackupPath]);
end;

function TFileSystemAdapter.CreateBackupPath(const AFilePath: string): string;
begin
  Result := TPath.GetFullPath(AFilePath) + '.atropos-' +
    FManifest.TransactionId + '.bak';
end;

procedure TFileSystemAdapter.EnsureManifest(const AFilePath: string);
begin
  if Assigned(FManifest) then
    Exit;
  if FTransactionRoot.IsEmpty then
    FTransactionRoot := TPath.GetDirectoryName(TPath.GetFullPath(AFilePath));
  FManifest := TFileTransactionManifest.CreateNew(GetManifestPath);
end;

function TFileSystemAdapter.GetManifestPath: string;
begin
  Result := TPath.Combine(FTransactionRoot, '.atropos-transaction.json');
end;

function TFileSystemAdapter.IsExpectedBackupPath(const AOriginalPath,
  ABackupPath, ATransactionId: string): Boolean;
begin
  Result := SameText(ABackupPath, AOriginalPath + '.atropos-' +
    ATransactionId + '.bak');
end;

procedure TFileSystemAdapter.ReleaseTransactionLock;
begin
  FreeAndNil(FTransactionLock);
  if FLockPath.IsEmpty or not TFile.Exists(FLockPath) then
    Exit;
  TFile.Delete(FLockPath);
  FLockPath := EmptyStr;
end;

procedure TFileSystemAdapter.RecoverPendingBackups(const ARootDirectory: string);
var
  LLockPath: string;
  LManifest: TFileTransactionManifest;
begin
  if not TDirectory.Exists(ARootDirectory) then
    Exit;
  FTransactionRoot := TPath.GetFullPath(ARootDirectory);
  LLockPath := TPath.Combine(FTransactionRoot, '.atropos.lock');
  FTransactionLock := TFileStream.Create(LLockPath, fmCreate or fmShareExclusive);
  FLockPath := LLockPath;
  try
    if not TFile.Exists(GetManifestPath) then
    begin
      RejectLegacyBackups(FTransactionRoot);
      Exit;
    end;
    LManifest := TFileTransactionManifest.Load(GetManifestPath);
    try
      if SameText(LManifest.State, 'committed') then
        CleanupCommittedTransaction(LManifest);
      if SameText(LManifest.State, 'active') then
        RestoreManifest(LManifest);
    finally
      LManifest.Free;
    end;
  except
    ReleaseTransactionLock;
    raise;
  end;
end;

procedure TFileSystemAdapter.RejectLegacyBackups(
  const ARootDirectory: string);
var
  LBackups: TArray<string>;
begin
  LBackups := TDirectory.GetFiles(ARootDirectory, '*.atropos-*.bak',
    TSearchOption.soAllDirectories);
  if Length(LBackups) = 0 then
    Exit;
  raise Exception.CreateFmt(
    'Legacy Atropos backups were found without a transaction manifest. ' +
    'They were preserved for manual recovery: %s', [LBackups[0]]);
end;

procedure TFileSystemAdapter.RestoreManifestEntry(
  const AEntry: TFileTransactionEntry; const ATransactionId: string);
begin
  if not TFile.Exists(AEntry.BackupPath) then
    Exit;
  TFile.Copy(AEntry.BackupPath, AEntry.OriginalPath, True);
  TFile.Delete(AEntry.BackupPath);
end;

procedure TFileSystemAdapter.ValidateManifestEntry(
  const AEntry: TFileTransactionEntry; const ATransactionId: string);
begin
  if not IsExpectedBackupPath(AEntry.OriginalPath, AEntry.BackupPath,
    ATransactionId) then
    raise Exception.Create('Transaction manifest contains an invalid backup path.');
  if not TFile.Exists(AEntry.BackupPath) then
  begin
    if TFile.Exists(AEntry.OriginalPath) and SameText(
      TFileTransactionManifest.HashFile(AEntry.OriginalPath),
      AEntry.OriginalHash) then
      Exit;
    raise Exception.CreateFmt('Transaction backup is missing: %s',
      [AEntry.BackupPath]);
  end;
  if not SameText(TFileTransactionManifest.HashFile(AEntry.BackupPath),
    AEntry.OriginalHash) then
    raise Exception.CreateFmt('Transaction backup hash mismatch: %s',
      [AEntry.BackupPath]);
end;

procedure TFileSystemAdapter.RestoreManifest(
  AManifest: TFileTransactionManifest);
var
  LEntry: TFileTransactionEntry;
begin
  for LEntry in AManifest.Entries do
    ValidateManifestEntry(LEntry, AManifest.TransactionId);
  for LEntry in AManifest.Entries do
    RestoreManifestEntry(LEntry, AManifest.TransactionId);
  AManifest.Delete;
end;

procedure TFileSystemAdapter.CleanupCommittedTransaction(
  AManifest: TFileTransactionManifest);
var
  LEntry: TFileTransactionEntry;
begin
  for LEntry in AManifest.Entries do
    if not IsExpectedBackupPath(LEntry.OriginalPath, LEntry.BackupPath,
      AManifest.TransactionId) then
      raise Exception.Create('Transaction manifest contains an invalid backup path.');
  for LEntry in AManifest.Entries do
  begin
    if TFile.Exists(LEntry.BackupPath) then
      TFile.Delete(LEntry.BackupPath);
  end;
  AManifest.Delete;
end;

procedure TFileSystemAdapter.RestoreBackups;
begin
  try
    if Assigned(FManifest) then
      RestoreManifest(FManifest);
  finally
    FreeAndNil(FManifest);
    ReleaseTransactionLock;
  end;
end;

procedure TFileSystemAdapter.CommitBackups;
begin
  try
    if Assigned(FManifest) then
    begin
      FManifest.MarkCommitted;
      CleanupCommittedTransaction(FManifest);
    end;
  finally
    FreeAndNil(FManifest);
    ReleaseTransactionLock;
  end;
end;

function TFileSystemAdapter.ReadFileContent(const AFilePath: string): string;
begin
  if not TFile.Exists(AFilePath) then
    raise Exception.CreateFmt('Cannot read. File does not exist: %s', [AFilePath]);

  Result := TFile.ReadAllText(AFilePath, TSourceEncoding.Detect(TFile.ReadAllBytes(AFilePath)));
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

  if TSourceEncoding.IsValidUTF8(LBytes) then
  begin
    TFile.WriteAllBytes(AFilePath, TEncoding.UTF8.GetBytes(AContent));
    Exit;
  end;

  TFile.WriteAllText(AFilePath, AContent, TEncoding.Default);
end;

end.
