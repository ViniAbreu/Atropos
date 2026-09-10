unit Atropos.Adapters.ProjectSourceMappings;

interface

uses Atropos.Core.Ports, Atropos.Core.Compilation;

type
  TProjectSourceMappings = class
  public
    class function Resolve(const AContext: TProjectCompilationContext;
      const AParser: IASTParser): TProjectCompilationContext; static;
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections;

class function TProjectSourceMappings.Resolve(const AContext: TProjectCompilationContext;
  const AParser: IASTParser): TProjectCompilationContext;
var
  LTree: IUnitSyntaxTree;
  LImports: IProjectSourceImports;
  LDiagnostics: IUnitAnalysisDiagnostics;
  LMapping, LInput: TUnitSourceMapping;
  LNames: TDictionary<string, string>;
  LPaths: TList<string>;
  LMappings: TList<TUnitSourceMapping>;
begin
  Result := AContext;
  if AContext.MainSource.IsEmpty then
    Exit;
  LTree := AParser.ParseFile(AContext.MainSource);
  if Supports(LTree, IUnitAnalysisDiagnostics, LDiagnostics) then
    if Length(LDiagnostics.GetIncompleteAnalysisReasons) > 0 then
      raise EInvalidOperation.Create('Incomplete project source: ' +
        string.Join('; ', LDiagnostics.GetIncompleteAnalysisReasons));
  if not Supports(LTree, IProjectSourceImports, LImports) then
    raise EInvalidOperation.Create('Parser cannot extract project source mappings.');
  LNames := TDictionary<string, string>.Create;
  LPaths := TList<string>.Create;
  LMappings := TList<TUnitSourceMapping>.Create;
  try
    LPaths.AddRange(AContext.UnitPaths);
    for LInput in LImports.GetProjectImports do
    begin
      LMapping := LInput;
      if LMapping.FilePath.IsEmpty then
        Continue;
      LMapping.FilePath := TPath.GetFullPath(TPath.Combine(
        TPath.GetDirectoryName(AContext.ProjectPath), LMapping.FilePath));
      if LNames.ContainsKey(LMapping.UnitName.ToLowerInvariant) then
        raise EInvalidOperation.Create('Duplicate project source mapping: ' + LMapping.UnitName);
      if not TFile.Exists(LMapping.FilePath) then
        raise EFileNotFoundException.Create('Mapped project source not found: ' + LMapping.FilePath);
      LNames.Add(LMapping.UnitName.ToLowerInvariant, LMapping.FilePath);
      LMappings.Add(LMapping);
      if not LPaths.Contains(LMapping.FilePath) then
        LPaths.Add(LMapping.FilePath);
    end;
    Result.SourceMappings := LMappings.ToArray;
    Result.UnitPaths := LPaths.ToArray;
  finally
    LMappings.Free;
    LPaths.Free;
    LNames.Free;
  end;
end;

end.
