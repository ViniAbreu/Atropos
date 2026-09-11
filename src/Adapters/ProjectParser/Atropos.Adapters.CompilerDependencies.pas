unit Atropos.Adapters.CompilerDependencies;

interface

type
  TCompilerDependency = record
    FilePath, ReportedPath: string;
  end;

  TCompilerDependencies = class
  public
    class function Read(const APath: string; const AOutputPath: string = ''): TArray<string>; static;
    class function ReadEntries(const APath, AOutputPath: string): TArray<TCompilerDependency>; static;
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils, System.RegularExpressions,
  System.Generics.Collections, Atropos.Adapters.DelphiSource;

class function TCompilerDependencies.Read(const APath, AOutputPath: string): TArray<string>;
var LEntries: TArray<TCompilerDependency>; I: Integer;
begin
  LEntries := ReadEntries(APath, AOutputPath);
  SetLength(Result, Length(LEntries));
  for I := 0 to High(LEntries) do Result[I] := LEntries[I].FilePath;
end;

class function TCompilerDependencies.ReadEntries(const APath, AOutputPath: string): TArray<TCompilerDependency>;
var LSource: TDelphiSourceContent; LLines: TList<TCompilerDependency>; LEntry: TCompilerDependency;
  LLine, LRawLine, LResolved, LGenerated: string; LHeader: Boolean;
begin
  LSource := TDelphiSourceReader.ReadRaw(APath);
  LLines := TList<TCompilerDependency>.Create;
  try
    LHeader := False;
    for LRawLine in LSource.Text.Split([#10]) do
    begin
      LLine := LRawLine.Trim;
      if LLine.IsEmpty then Continue;
      if not LHeader then
      begin
        if not TRegEx.IsMatch(LLine, '^.+\.exe:(?:\s|$)', [roIgnoreCase]) then
          raise EInvalidOperation.Create('Unrecognized compiler dependency header.');
        LHeader := True;
        Continue;
      end;
      if LLine.EndsWith('\') then LLine := Copy(LLine, 1, Length(LLine) - 1).TrimRight;
      if TPath.IsRelativePath(LLine) then
        raise EInvalidOperation.Create('Unresolved compiler dependency: ' + LLine);
      LResolved := LLine;
      if not AOutputPath.IsEmpty then
      begin
        LGenerated := TPath.Combine(AOutputPath, TPath.GetFileName(LLine));
        if TFile.Exists(LGenerated) then LResolved := LGenerated;
      end;
      if not TFile.Exists(LResolved) then
        raise EInvalidOperation.Create('Unresolved compiler dependency: ' + LLine);
      LEntry.FilePath := TPath.GetFullPath(LResolved);
      LEntry.ReportedPath := TPath.GetFullPath(LLine);
      LLines.Add(LEntry);
    end;
    if LLines.Count = 0 then raise EInvalidOperation.Create('Compiler returned no dependency files.');
    Result := LLines.ToArray;
  finally
    LLines.Free;
  end;
end;

end.
