unit Atropos.Core.Modifier;

interface
uses
  Atropos.Core.Ports, Atropos.Core.Domain, Atropos.Core.Config;

type
  TApplyUsesChanges = class
  private
    FFileService: IFileService;
    FConfig: TToolConfig;
    class function RemoveUnitSurgically(const ASource, AUnitToRemove: string): string;
    class function RemoveUnitFromUsesClause(const ASource, AUnitToRemove: string; AIsInterface: Boolean): string;
    class function AddUnitToImplementationUses(const ASource, AUnitToAdd: string): string;
  public
    constructor Create(AFileService: IFileService; AConfig: TToolConfig);
    procedure Execute(const AFilePath: string; const AAnalysisResult: TUnitAnalysisResult);
  end;

implementation
uses
  System.RegularExpressions;



constructor TApplyUsesChanges.Create(AFileService: IFileService; AConfig: TToolConfig);
begin
  FFileService := AFileService;
  FConfig := AConfig;
end;

class function TApplyUsesChanges.RemoveUnitSurgically(const ASource, AUnitToRemove: string): string;
var
  LEscapedUnit: string;
  LRegex: TRegEx;
  LBoundary: string;
begin
  Result := ASource;
  LEscapedUnit := TRegEx.Escape(AUnitToRemove);
  
  
  LBoundary := '(?<![\w\.])' + LEscapedUnit + '(?![\w\.])';
  
  
  LRegex := TRegEx.Create('(?i)' + LBoundary + '\s*,\s*');
  if LRegex.IsMatch(Result) then
  begin
    Result := LRegex.Replace(Result, '');
    Exit;
  end;

  
  LRegex := TRegEx.Create('(?i),\s*' + LBoundary);
  if LRegex.IsMatch(Result) then
  begin
    Result := LRegex.Replace(Result, '');
    Exit;
  end;

  
  LRegex := TRegEx.Create('(?i)' + LBoundary);
  if LRegex.IsMatch(Result) then
  begin
    Result := LRegex.Replace(Result, '');
  end;
end;

class function TApplyUsesChanges.RemoveUnitFromUsesClause(const ASource, AUnitToRemove: string; AIsInterface: Boolean): string;
var
  LUsesPos, LSemiPos, LSearchStart: Integer;
  LUsesText, LNewUsesText: string;
  LMatch, LSectionMatch: TMatch;
  LRegex: TRegEx;
begin
  Result := ASource;
  
  if AIsInterface then
    LSectionMatch := TRegEx.Match(ASource, '^\s*interface\b', [roIgnoreCase, roMultiLine])
  else
    LSectionMatch := TRegEx.Match(ASource, '^\s*implementation\b', [roIgnoreCase, roMultiLine]);
    
  if not LSectionMatch.Success then Exit;
  LSearchStart := LSectionMatch.Index;
  
  
  LRegex := TRegEx.Create('^\s*uses\b', [roIgnoreCase, roMultiLine]);
  LMatch := LRegex.Match(ASource, LSearchStart);
  if not LMatch.Success then Exit;
  
  LUsesPos := LMatch.Index;
  
  
  if AIsInterface then
  begin
    var LImplMatch := TRegEx.Match(ASource, '^\s*implementation\b', [roIgnoreCase, roMultiLine]);
    if LImplMatch.Success and (LUsesPos > LImplMatch.Index) then Exit; 
  end;

  LSemiPos := Pos(';', ASource, LUsesPos);
  if LSemiPos = 0 then Exit;
  
  LUsesText := Copy(ASource, LUsesPos, LSemiPos - LUsesPos + 1);
  LNewUsesText := RemoveUnitSurgically(LUsesText, AUnitToRemove);
  
  if TRegEx.IsMatch(LNewUsesText, '(?i)^\s*uses\s*;\s*$') then
    LNewUsesText := '';
    
  Result := Copy(ASource, 1, LUsesPos - 1) + LNewUsesText + Copy(ASource, LSemiPos + 1, MaxInt);
end;

class function TApplyUsesChanges.AddUnitToImplementationUses(const ASource, AUnitToAdd: string): string;
var
  LImplPos, LUsesPos, LSemiPos: Integer;
  LMatch, LImplMatch: TMatch;
  LRegex: TRegEx;
begin
  Result := ASource;
  LImplMatch := TRegEx.Match(ASource, '^\s*implementation\b', [roIgnoreCase, roMultiLine]);
  if not LImplMatch.Success then Exit;
  LImplPos := LImplMatch.Index;
  
  
  LRegex := TRegEx.Create('^\s*uses\b', [roIgnoreCase, roMultiLine]);
  LMatch := LRegex.Match(ASource, LImplPos);
  
  if LMatch.Success then
  begin
    
    LUsesPos := LMatch.Index;
    LSemiPos := Pos(';', ASource, LUsesPos);
    if LSemiPos > 0 then
    begin
      
      var LUsesClauseText := Copy(ASource, LUsesPos, LSemiPos - LUsesPos + 1);
      if TRegEx.IsMatch(LUsesClauseText, '(?i)(?<![\w\.])' + TRegEx.Escape(AUnitToAdd) + '(?![\w\.])') then
        Exit; 

      Result := Copy(ASource, 1, LSemiPos - 1) + ', ' + AUnitToAdd + Copy(ASource, LSemiPos, MaxInt);
      Exit;
    end;
  end;
  
  
  Result := Copy(ASource, 1, LImplPos + LImplMatch.Length - 1) + sLineBreak + 'uses' + sLineBreak + '  ' + AUnitToAdd + ';' + Copy(ASource, LImplPos + LImplMatch.Length, MaxInt);
end;

procedure TApplyUsesChanges.Execute(const AFilePath: string; const AAnalysisResult: TUnitAnalysisResult);
var
  LContent, LUnit: string;
begin
  
  FFileService.BackupFile(AFilePath);
  
  
  LContent := FFileService.ReadFileContent(AFilePath);
  
  
  if FConfig.RemoveUnused then
  begin
    for LUnit in AAnalysisResult.UnusedUnits do
    begin
      LContent := RemoveUnitFromUsesClause(LContent, LUnit, True);
      LContent := RemoveUnitFromUsesClause(LContent, LUnit, False);
    end;
  end;
  
  
  if FConfig.MoveToImplementation then
  begin
    for LUnit in AAnalysisResult.UnitsToMoveToImpl do
    begin
      LContent := RemoveUnitFromUsesClause(LContent, LUnit, True);
      LContent := AddUnitToImplementationUses(LContent, LUnit);
    end;
  end;
  
  
  FFileService.WriteFileContent(AFilePath, LContent);
end;

end.


