unit Atropos.Adapters.SourceIncludes;

interface

uses System.Generics.Collections, Atropos.Core.Ports,
  SimpleParser.Lexer.Types, Atropos.Adapters.SourceSnapshot;

type
  TSourceIncludeResolver = class(TInterfacedObject, IIncludeHandler)
  private
    FRootFile: string;
    FIncludePaths: TArray<string>;
    FAncestors: TList<string>;
    FDependencies: TList<TSourceDependency>;
    FSnapshot: TSourceSnapshot;
    function ResolveInclude(const AParentFile, AIncludeName: string): string;
    function FindInclude(const AParentFile, AIncludeName: string): string;
    procedure CheckCycle(const AParentFile, AFilePath: string);
    procedure RecordDependency(const AParentFile, AFilePath, AHash: string);
  public
    constructor Create(const ARootFile: string; const AIncludePaths: TArray<string>;
      ASnapshot: TSourceSnapshot = nil);
    destructor Destroy; override;
    function GetIncludeFileContent(const ParentFileName, IncludeName: string;
      out Content, FileName: string): Boolean;
    function GetDependencies: TArray<TSourceDependency>;
    function GetRawIncludeFileContent(const ParentFileName, IncludeName: string;
      out Content, FileName: string): Boolean;
  end;

implementation

uses System.SysUtils, System.IOUtils, Atropos.Adapters.DelphiSource;

constructor TSourceIncludeResolver.Create(const ARootFile: string;
  const AIncludePaths: TArray<string>; ASnapshot: TSourceSnapshot);
begin
  inherited Create;
  FRootFile := TPath.GetFullPath(ARootFile);
  FSnapshot := ASnapshot;
  FIncludePaths := Copy(AIncludePaths);
  FAncestors := TList<string>.Create;
  FAncestors.Add(FRootFile);
  FDependencies := TList<TSourceDependency>.Create;
end;

destructor TSourceIncludeResolver.Destroy;
begin
  FDependencies.Free;
  FAncestors.Free;
  inherited;
end;

function TSourceIncludeResolver.FindInclude(const AParentFile,
  AIncludeName: string): string;
var
  LPath: string;
  LDirectory: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(AParentFile),
    AIncludeName));
  if TFile.Exists(Result) then
    Exit;
  if Assigned(FSnapshot) then
    FSnapshot.RecordMissingSource(Result);
  for LPath in FIncludePaths do
  begin
    LDirectory := LPath;
    if TPath.IsRelativePath(LDirectory) then
      LDirectory := TPath.Combine(TPath.GetDirectoryName(FRootFile), LDirectory);
    Result := TPath.GetFullPath(TPath.Combine(LDirectory, AIncludeName));
    if TFile.Exists(Result) then
      Exit;
    if Assigned(FSnapshot) then
      FSnapshot.RecordMissingSource(Result);
  end;
  Result := '';
end;

function TSourceIncludeResolver.ResolveInclude(const AParentFile, AIncludeName: string): string;
begin
  Result := FindInclude(AParentFile, AIncludeName);
  if Result.IsEmpty then
    raise EIncludeError.CreateFmt('Include "%s" requested by "%s" was not found.',
      [AIncludeName, AParentFile]);
end;

function TSourceIncludeResolver.GetRawIncludeFileContent(const ParentFileName, IncludeName: string;
  out Content, FileName: string): Boolean;
var LParent: string; LSource: TDelphiSourceContent;
begin
  LParent := ParentFileName;
  if LParent.IsEmpty then LParent := FRootFile;
  FileName := FindInclude(LParent, IncludeName);
  Content := '';
  Result := not FileName.IsEmpty;
  if not Result then Exit;
  LSource := TDelphiSourceReader.ReadRaw(FileName);
  if Assigned(FSnapshot) then FSnapshot.RecordSource(FileName, LSource.ContentHash);
  RecordDependency(LParent, FileName, LSource.ContentHash);
  Content := LSource.Text;
end;

procedure TSourceIncludeResolver.CheckCycle(const AParentFile,
  AFilePath: string);
var
  LIndex: Integer;
  LAncestor: string;
begin
  for LIndex := FAncestors.Count - 1 downto 0 do
  begin
    if not SameText(FAncestors[LIndex], AParentFile) then
      Continue;
    while FAncestors.Count > LIndex + 1 do
      FAncestors.Delete(FAncestors.Count - 1);
    Break;
  end;
  for LAncestor in FAncestors do
  begin
    if SameText(LAncestor, AFilePath) then
      raise EIncludeError.CreateFmt('Include cycle detected: "%s" -> "%s".',
        [AParentFile, AFilePath]);
  end;
  if FAncestors.Count >= 128 then
    raise EIncludeError.Create('Include nesting exceeds 128 files.');
  FAncestors.Add(AFilePath);
end;

procedure TSourceIncludeResolver.RecordDependency(const AParentFile,
  AFilePath, AHash: string);
var
  LDependency: TSourceDependency;
begin
  for LDependency in FDependencies do
  begin
    if SameText(LDependency.ParentPath, AParentFile) and
      SameText(LDependency.FilePath, AFilePath) and
      (LDependency.ContentHash = AHash) then
      Exit;
  end;
  LDependency.ParentPath := AParentFile;
  LDependency.FilePath := AFilePath;
  LDependency.ContentHash := AHash;
  FDependencies.Add(LDependency);
end;

function TSourceIncludeResolver.GetIncludeFileContent(
  const ParentFileName, IncludeName: string; out Content, FileName: string): Boolean;
var
  LParentFile: string;
  LSource: TDelphiSourceContent;
begin
  LParentFile := ParentFileName;
  if LParentFile.IsEmpty then
    LParentFile := FRootFile;
  FileName := ResolveInclude(LParentFile, IncludeName);
  CheckCycle(LParentFile, FileName);
  LSource := TDelphiSourceReader.Read(FileName);
  if Assigned(FSnapshot) then
    FSnapshot.RecordSource(FileName, LSource.ContentHash);
  Content := LSource.Text;
  RecordDependency(LParentFile, FileName, LSource.ContentHash);
  Result := True;
end;

function TSourceIncludeResolver.GetDependencies: TArray<TSourceDependency>;
begin
  Result := FDependencies.ToArray;
end;

end.
