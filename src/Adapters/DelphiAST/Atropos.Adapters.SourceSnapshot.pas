unit Atropos.Adapters.SourceSnapshot;

interface

uses System.Generics.Collections;

type
  TSourceSnapshot = class
  private
    FHashes: TDictionary<string, string>;
    FAbsentSources: TDictionary<string, Boolean>;
    FActive: Boolean;
    FConflict: string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure BeginAnalysis;
    procedure RecordSource(const APath, AHash: string);
    procedure RecordMissingSource(const APath: string);
    procedure ValidateAnalysis;
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils, System.Hash;

constructor TSourceSnapshot.Create;
begin
  inherited;
  FHashes := TDictionary<string, string>.Create;
  FAbsentSources := TDictionary<string, Boolean>.Create;
end;

destructor TSourceSnapshot.Destroy;
begin
  FHashes.Free;
  FAbsentSources.Free;
  inherited;
end;

procedure TSourceSnapshot.BeginAnalysis;
begin
  FHashes.Clear;
  FAbsentSources.Clear;
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
  if FAbsentSources.ContainsKey(LPath) then
    FConflict := LPath + ' appeared after include resolution';
  if not FHashes.TryGetValue(LPath, LPrevious) then
  begin
    FHashes.Add(LPath, AHash.ToLowerInvariant);
    Exit;
  end;
  if LPrevious <> AHash.ToLowerInvariant then
    FConflict := LPath;
end;

procedure TSourceSnapshot.RecordMissingSource(const APath: string);
var LPath: string;
begin
  if not FActive then
    Exit;
  LPath := TPath.GetFullPath(APath).ToLowerInvariant;
  if FHashes.ContainsKey(LPath) then
    FConflict := LPath + ' disappeared during include resolution';
  FAbsentSources.AddOrSetValue(LPath, True);
end;

procedure TSourceSnapshot.ValidateAnalysis;
var
  LSource: TPair<string, string>;
  LPath: string;
begin
  if not FConflict.IsEmpty then
    raise EInvalidOperation.Create('Source changed during analysis: ' + FConflict);
  for LPath in FAbsentSources.Keys do
    if TFile.Exists(LPath) then
    begin
      FConflict := LPath + ' appeared after include resolution';
      raise EInvalidOperation.Create('Source changed during analysis: ' + FConflict);
    end;
  for LSource in FHashes do
  begin
    if not TFile.Exists(LSource.Key) then
      raise EInvalidOperation.Create('Analyzed source no longer exists: ' + LSource.Key);
    if THashSHA2.GetHashStringFromFile(LSource.Key) <> LSource.Value then
      raise EInvalidOperation.Create('Source changed before applying analysis: ' + LSource.Key);
  end;
end;

end.
