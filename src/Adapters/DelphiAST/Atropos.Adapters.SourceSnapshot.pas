unit Atropos.Adapters.SourceSnapshot;

interface

uses System.Generics.Collections;

type
  TSourceSnapshot = class
  private
    FHashes: TDictionary<string, string>;
    FActive: Boolean;
    FConflict: string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure BeginAnalysis;
    procedure RecordSource(const APath, AHash: string);
    procedure ValidateAnalysis;
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils, System.Hash;

constructor TSourceSnapshot.Create;
begin
  inherited;
  FHashes := TDictionary<string, string>.Create;
end;

destructor TSourceSnapshot.Destroy;
begin
  FHashes.Free;
  inherited;
end;

procedure TSourceSnapshot.BeginAnalysis;
begin
  FHashes.Clear;
  FConflict := '';
  FActive := True;
end;

procedure TSourceSnapshot.RecordSource(const APath, AHash: string);
var
  LPath, LPrevious: string;
begin
  if not FActive then
    Exit;
  LPath := TPath.GetFullPath(APath).ToLowerInvariant;
  if not FHashes.TryGetValue(LPath, LPrevious) then
  begin
    FHashes.Add(LPath, AHash);
    Exit;
  end;
  if LPrevious <> AHash then
    FConflict := LPath;
end;

procedure TSourceSnapshot.ValidateAnalysis;
var
  LSource: TPair<string, string>;
begin
  if not FConflict.IsEmpty then
    raise EInvalidOperation.Create('Source changed during analysis: ' + FConflict);
  for LSource in FHashes do
  begin
    if not TFile.Exists(LSource.Key) then
      raise EInvalidOperation.Create('Analyzed source no longer exists: ' + LSource.Key);
    if THashSHA2.GetHashStringFromFile(LSource.Key) <> LSource.Value then
      raise EInvalidOperation.Create('Source changed before applying analysis: ' + LSource.Key);
  end;
end;

end.
