unit Atropos.Adapters.CompilerSourceInputs;

interface

uses System.Generics.Collections, Atropos.Core.Ports, Atropos.Core.Compilation,
  Atropos.Adapters.SourceSnapshot, Atropos.Adapters.SourceIncludes;

type
  TCompilerSourceInputs = class
  private
    FSnapshot: TSourceSnapshot;
    FIncludes: TSourceIncludeResolver;
    FContext: TProjectCompilationContext;
    FVisited: TDictionary<string, Boolean>;
    FCancel: TCancellationCheck;
    procedure ReadSource(const APath, AUnitPath: string);
    procedure ReadDirective(const AText, APath, AUnitPath: string);
    procedure ReadInclude(const AName, APath, AUnitPath: string);
    procedure RecordBinary(const AName, APath, AUnitPath: string; const APaths: TArray<string>);
    class function Arguments(const AText: string): TArray<string>; static;
  public
    constructor Create(ASnapshot: TSourceSnapshot; AIncludes: TSourceIncludeResolver;
      const AContext: TProjectCompilationContext; const ACancel: TCancellationCheck = nil);
    destructor Destroy; override;
    procedure Capture(const APath: string);
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils, System.Hash, System.RegularExpressions,
  Atropos.Core.SourceTokens, Atropos.Adapters.DelphiSource;

constructor TCompilerSourceInputs.Create(ASnapshot: TSourceSnapshot;
  AIncludes: TSourceIncludeResolver; const AContext: TProjectCompilationContext;
  const ACancel: TCancellationCheck);
begin
  inherited Create;
  FSnapshot := ASnapshot;
  FIncludes := AIncludes;
  FContext := AContext;
  FCancel := ACancel;
  FVisited := TDictionary<string, Boolean>.Create;
end;

destructor TCompilerSourceInputs.Destroy;
begin
  FVisited.Free;
  inherited;
end;

class function TCompilerSourceInputs.Arguments(const AText: string): TArray<string>;
var LMatch: TMatch; LItems: TList<string>; LText: string;
begin
  LItems := TList<string>.Create;
  try
    for LMatch in TRegEx.Matches(AText, '''[^'']*''|"[^"]*"|\S+') do
    begin
      LText := LMatch.Value;
      if CharInSet(LText[1], ['''', '"']) then LText := Copy(LText, 2, Length(LText) - 2);
      LItems.Add(LText);
    end;
    Result := LItems.ToArray;
  finally
    LItems.Free;
  end;
end;

procedure TCompilerSourceInputs.ReadInclude(const AName, APath, AUnitPath: string);
var LContent, LPath: string;
begin
  if FIncludes.GetRawIncludeFileContent(APath, AName, LContent, LPath) then
    ReadSource(LPath, AUnitPath);
end;

procedure TCompilerSourceInputs.RecordBinary(const AName, APath, AUnitPath: string;
  const APaths: TArray<string>);
var LName, LDirectory, LPath: string; LDirectories: TArray<string>;
begin
  LName := AName.Replace('*', TPath.GetFileNameWithoutExtension(AUnitPath));
  LDirectories := [TPath.GetDirectoryName(APath), TPath.GetDirectoryName(AUnitPath),
    TPath.GetDirectoryName(FContext.ProjectPath)] + APaths;
  for LDirectory in LDirectories do
  begin
    LPath := TPath.GetFullPath(TPath.Combine(LDirectory, LName));
    if FSnapshot.ContainsSource(LPath) then Continue;
    if not TFile.Exists(LPath) then
    begin
      FSnapshot.RecordMissingSource(LPath);
      Continue;
    end;
    FSnapshot.RecordSource(LPath, THashSHA2.GetHashStringFromFile(LPath));
  end;
end;

procedure TCompilerSourceInputs.ReadDirective(const AText, APath, AUnitPath: string);
var LBody, LName, LArgument: string; LArguments: TArray<string>; I: Integer;
begin
  LBody := Copy(AText, 3, Length(AText) - 3);
  if AText.StartsWith('(*$') then LBody := Copy(AText, 4, Length(AText) - 5);
  LArguments := Arguments(LBody.Trim);
  if Length(LArguments) < 2 then Exit;
  LName := LArguments[0].ToUpperInvariant;
  if (LName = 'INCLUDEPATH') or (LName = 'INCPATH') then
    raise EInvalidOperation.Create('Source changes its include search path: ' + APath);
  for I := 1 to High(LArguments) do
  begin
    LArgument := LArguments[I];
    if (LName = 'I') or (LName = 'INCLUDE') then ReadInclude(LArgument, APath, AUnitPath);
    if (LName = 'R') or (LName = 'RESOURCE') then
      RecordBinary(LArgument, APath, AUnitPath, FContext.ResourcePaths);
    if (LName = 'L') or (LName = 'LINK') then
      RecordBinary(LArgument, APath, AUnitPath, FContext.ObjectPaths);
  end;
end;

procedure TCompilerSourceInputs.ReadSource(const APath, AUnitPath: string);
var LSource: TDelphiSourceContent; LTokenizer: TSourceTokenizer;
  LToken: TSourceToken; LKey: string;
begin
  if Assigned(FCancel) then
    if FCancel() then raise EAbort.Create('Compiler source capture cancelled.');
  // The owner matters for wildcard resources in shared include files.
  LKey := TPath.GetFullPath(APath).ToLowerInvariant + #0 + AUnitPath.ToLowerInvariant;
  if FVisited.ContainsKey(LKey) then Exit;
  FVisited.Add(LKey, True);
  LSource := TDelphiSourceReader.ReadRaw(APath);
  FSnapshot.RecordSource(APath, LSource.ContentHash);
  LTokenizer := TSourceTokenizer.Create;
  try
    for LToken in LTokenizer.Read(LSource.Text) do
      if LToken.Kind = stDirective then ReadDirective(LToken.Text, APath, AUnitPath);
  finally
    LTokenizer.Free;
  end;
end;

procedure TCompilerSourceInputs.Capture(const APath: string);
begin
  ReadSource(APath, APath);
end;

end.
