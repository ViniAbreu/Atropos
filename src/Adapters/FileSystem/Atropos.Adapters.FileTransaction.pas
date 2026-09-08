unit Atropos.Adapters.FileTransaction;

interface

uses
  System.Generics.Collections,
  System.SysUtils;

type
  TFileTransactionEntry = record
    OriginalPath: string;
    BackupPath: string;
    OriginalHash: string;
  end;

  TFileTransactionManifest = class
  private
    FEntries: TList<TFileTransactionEntry>;
    FCreatedUtc: string;
    FFilePath: string;
    FState: string;
    FTransactionId: string;
    class function ReadRequiredString(AObject: TObject;
      const AName: string): string; static;
    procedure LoadFromFile;
  public
    constructor CreateNew(const AFilePath: string);
    destructor Destroy; override;
    procedure AddEntry(const AEntry: TFileTransactionEntry);
    procedure Delete;
    function HasOriginal(const AOriginalPath: string): Boolean;
    procedure MarkCommitted;
    procedure Save;
    class function HashFile(const AFilePath: string): string; static;
    class function Load(const AFilePath: string): TFileTransactionManifest; static;
    property Entries: TList<TFileTransactionEntry> read FEntries;
    property State: string read FState;
    property TransactionId: string read FTransactionId;
  end;

implementation

uses
  System.Classes,
  System.DateUtils,
  System.Hash,
  System.IOUtils,
  System.JSON,
  Winapi.Windows;

const
  MANIFEST_VERSION = 1;
  STATE_ACTIVE = 'active';
  STATE_COMMITTED = 'committed';

constructor TFileTransactionManifest.CreateNew(const AFilePath: string);
begin
  inherited Create;
  FEntries := TList<TFileTransactionEntry>.Create;
  FFilePath := AFilePath;
  FState := STATE_ACTIVE;
  FTransactionId := TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '');
  FCreatedUtc := DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True);
end;

class function TFileTransactionManifest.Load(
  const AFilePath: string): TFileTransactionManifest;
begin
  Result := TFileTransactionManifest.CreateNew(AFilePath);
  try
    Result.LoadFromFile;
  except
    Result.Free;
    raise;
  end;
end;

destructor TFileTransactionManifest.Destroy;
begin
  FEntries.Free;
  inherited;
end;

class function TFileTransactionManifest.ReadRequiredString(AObject: TObject;
  const AName: string): string;
var
  LJSONValue: TJSONValue;
begin
  LJSONValue := TJSONObject(AObject).GetValue(AName);
  if not Assigned(LJSONValue) or LJSONValue.Value.IsEmpty then
    raise Exception.CreateFmt('Transaction manifest field is missing: %s',
      [AName]);
  Result := LJSONValue.Value;
end;

procedure TFileTransactionManifest.LoadFromFile;
var
  LEntry: TFileTransactionEntry;
  LEntryObject: TJSONObject;
  LEntries: TJSONArray;
  LIndex: Integer;
  LRoot: TJSONObject;
  LValue: TJSONValue;
  LCreatedDate: TDateTime;
begin
  LValue := TJSONObject.ParseJSONValue(TFile.ReadAllText(FFilePath,
    TEncoding.UTF8));
  if not (LValue is TJSONObject) then
  begin
    LValue.Free;
    raise Exception.Create('Transaction manifest is not a JSON object.');
  end;
  LRoot := TJSONObject(LValue);
  try
    if StrToIntDef(ReadRequiredString(LRoot, 'version'), 0) <>
      MANIFEST_VERSION then
      raise Exception.Create('Unsupported transaction manifest version.');
    FTransactionId := ReadRequiredString(LRoot, 'transactionId');
    FState := ReadRequiredString(LRoot, 'state');
    FCreatedUtc := ReadRequiredString(LRoot, 'createdUtc');
    LCreatedDate := ISO8601ToDate(FCreatedUtc, False);
    if LCreatedDate <= 0 then
      raise Exception.Create('Invalid transaction manifest timestamp.');
    if not SameText(FState, STATE_ACTIVE) and
      not SameText(FState, STATE_COMMITTED) then
      raise Exception.Create('Invalid transaction manifest state.');
    LEntries := LRoot.GetValue('entries') as TJSONArray;
    if not Assigned(LEntries) then
      raise Exception.Create('Transaction manifest entries are missing.');
    for LIndex := 0 to LEntries.Count - 1 do
    begin
      if not (LEntries.Items[LIndex] is TJSONObject) then
        raise Exception.Create('Invalid transaction manifest entry.');
      LEntryObject := TJSONObject(LEntries.Items[LIndex]);
      LEntry.OriginalPath := ReadRequiredString(LEntryObject, 'original');
      LEntry.BackupPath := ReadRequiredString(LEntryObject, 'backup');
      LEntry.OriginalHash := ReadRequiredString(LEntryObject, 'sha256');
      FEntries.Add(LEntry);
    end;
  finally
    LRoot.Free;
  end;
end;

procedure TFileTransactionManifest.AddEntry(
  const AEntry: TFileTransactionEntry);
begin
  FEntries.Add(AEntry);
end;

procedure TFileTransactionManifest.Delete;
begin
  if TFile.Exists(FFilePath) then
    TFile.Delete(FFilePath);
end;

function TFileTransactionManifest.HasOriginal(
  const AOriginalPath: string): Boolean;
var
  LEntry: TFileTransactionEntry;
begin
  Result := False;
  for LEntry in FEntries do
    if SameText(LEntry.OriginalPath, AOriginalPath) then
      Exit(True);
end;

procedure TFileTransactionManifest.MarkCommitted;
begin
  FState := STATE_COMMITTED;
  Save;
end;

procedure TFileTransactionManifest.Save;
var
  LEntry: TFileTransactionEntry;
  LEntryObject: TJSONObject;
  LEntries: TJSONArray;
  LRoot: TJSONObject;
  LTemporaryPath: string;
begin
  LTemporaryPath := FFilePath + '.tmp';
  LRoot := TJSONObject.Create;
  try
    LRoot.AddPair('version', TJSONNumber.Create(MANIFEST_VERSION));
    LRoot.AddPair('transactionId', FTransactionId);
    LRoot.AddPair('state', FState);
    LRoot.AddPair('createdUtc', FCreatedUtc);
    LEntries := TJSONArray.Create;
    LRoot.AddPair('entries', LEntries);
    for LEntry in FEntries do
    begin
      LEntryObject := TJSONObject.Create;
      LEntryObject.AddPair('original', LEntry.OriginalPath);
      LEntryObject.AddPair('backup', LEntry.BackupPath);
      LEntryObject.AddPair('sha256', LEntry.OriginalHash);
      LEntries.AddElement(LEntryObject);
    end;
    TFile.WriteAllText(LTemporaryPath, LRoot.ToJSON, TEncoding.UTF8);
    if not MoveFileEx(PChar(LTemporaryPath), PChar(FFilePath),
      MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
      raise EOSError.CreateFmt('Cannot persist transaction manifest: %s',
        [SysErrorMessage(GetLastError)]);
  finally
    LRoot.Free;
    if TFile.Exists(LTemporaryPath) then
      TFile.Delete(LTemporaryPath);
  end;
end;

class function TFileTransactionManifest.HashFile(
  const AFilePath: string): string;
var
  LStream: TFileStream;
begin
  LStream := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyWrite);
  try
    Result := THashSHA2.GetHashString(LStream);
  finally
    LStream.Free;
  end;
end;

end.
