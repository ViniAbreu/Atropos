unit Atropos.Core.Modifier;

interface
uses
  Atropos.Core.Ports,
  Atropos.Core.Domain,
  Atropos.Core.Config;

type
  TApplyUsesChanges = class
  private
    FFileService: IFileService;
    FConfig: TToolConfig;
    class function RemoveUnitSafely(const ASource, AUnitToRemove: string): string;
    class function AddUnitToUsesClause(const ASource, AUnitToAdd: string; AIsInterface: Boolean): string;
    class function AddUnitToImplementationUses(const ASource, AUnitToAdd: string): string;
    class function GetDirectiveLevel(const ASource: string; AStartPos, AEndPos: Integer): Integer;
    class function GetDirectiveBlockStart(const ASource: string; AStartPos, ATargetPos: Integer): Integer;
    class function GetDirectiveBlockEnd(const ASource: string; AStartPos, ATargetPos: Integer): Integer;
    class function InjectUnconditionalUses(const ASource, AUnitToAdd: string; AWordPos: Integer): string;
    class function RewriteConditionalUses(const ASource, AUnitToAdd: string; AImplPos, AWordPos, ASemiPos: Integer): string;
    class function SanitizeUsesKeyword(const ASource: string; AWordPos, ASemiPos: Integer; out ANewSemiPos: Integer): string;
    class function RelocateSemicolon(const ASource: string; AImplPos, ASemiPos: Integer): string;
  public
    constructor Create(AFileService: IFileService; AConfig: TToolConfig);
    procedure Execute(const AFilePath: string; const AAnalysisResult: TUnitAnalysisResult);
    class function RemoveUnitFromUsesClause(const ASource, AUnitToRemove: string; AIsInterface: Boolean): string;
    class function AddUnitToInterfaceUses(const ASource, AUnitToAdd: string): string;
  end;

implementation
uses System.RegularExpressions,
  System.SysUtils;

constructor TApplyUsesChanges.Create(AFileService: IFileService; AConfig: TToolConfig);
begin
  FFileService := AFileService;
  FConfig := AConfig;
end;

class function TApplyUsesChanges.RemoveUnitSafely(const ASource, AUnitToRemove: string): string;
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
    Result := LRegex.Replace(Result, '');
end;

class function TApplyUsesChanges.RemoveUnitFromUsesClause(const ASource, AUnitToRemove: string; AIsInterface: Boolean): string;
var
  LUsesPos: Integer;
  LSemiPos: Integer;
  LSearchStart: Integer;
  LNewUsesText: string;
  LMatch: TMatch;
  LSectionMatch: TMatch;
  LImplMatch: TMatch;
  LRegex: TRegEx;
begin
  Result := ASource;
  
  if AIsInterface then
    LSectionMatch := TRegEx.Match(ASource, '^\s*interface\b', [roIgnoreCase, roMultiLine]);
  
  if not AIsInterface then
    LSectionMatch := TRegEx.Match(ASource, '^\s*implementation\b', [roIgnoreCase, roMultiLine]);
    
  if not LSectionMatch.Success then
    Exit;

  LSearchStart := LSectionMatch.Index;
  LRegex := TRegEx.Create('^\s*uses\b', [roIgnoreCase, roMultiLine]);
  LMatch := LRegex.Match(ASource, LSearchStart);
  if not LMatch.Success then
    Exit;
  
  LUsesPos := LMatch.Index;
  if AIsInterface then
  begin
    LImplMatch := TRegEx.Match(ASource, '^\s*implementation\b', [roIgnoreCase, roMultiLine]);
    if LImplMatch.Success and (LUsesPos > LImplMatch.Index) then
      Exit; 
  end;

  LSemiPos := Pos(';', ASource, LUsesPos);
  if LSemiPos = 0 then
    Exit;
  
  LNewUsesText := RemoveUnitSafely(Copy(ASource, LUsesPos, LSemiPos - LUsesPos + 1), AUnitToRemove);
  
  if TRegEx.IsMatch(LNewUsesText, '(?i)^\s*uses\s*;\s*$') then
    LNewUsesText := EmptyStr;
    
  Result := Copy(ASource, 1, LUsesPos - 1) + LNewUsesText + Copy(ASource, LSemiPos + 1, MaxInt);
end;

class function TApplyUsesChanges.GetDirectiveLevel(const ASource: string; AStartPos, AEndPos: Integer): Integer;
var
  LMatches: TMatchCollection;
  LMatch: TMatch;
  LVal: string;
begin
  Result := 0;
  LMatches := TRegEx.Matches(Copy(ASource, AStartPos, AEndPos - AStartPos + 1), '\{\$(IFDEF|IFNDEF|IF|ENDIF|IFEND)\b', [roIgnoreCase]);
  for LMatch in LMatches do
  begin
    LVal := LMatch.Value.ToUpper;
    if LVal.StartsWith('{$IFDEF') or LVal.StartsWith('{$IFNDEF') or LVal.StartsWith('{$IF') then
    begin
      Inc(Result);
      Continue;
    end;
      
    if LVal.StartsWith('{$ENDIF') or LVal.StartsWith('{$IFEND') then
      Dec(Result);
  end;
end;

class function TApplyUsesChanges.GetDirectiveBlockStart(const ASource: string; AStartPos, ATargetPos: Integer): Integer;
var
  LMatches: TMatchCollection;
  LMatch: TMatch;
  LVal: string;
  LDepth: Integer;
begin
  Result := ATargetPos;
  LDepth := 0;
  LMatches := TRegEx.Matches(Copy(ASource, AStartPos, ATargetPos - AStartPos + 1), '\{\$(IFDEF|IFNDEF|IF|ENDIF|IFEND)\b', [roIgnoreCase]);
  for LMatch in LMatches do
  begin
    LVal := LMatch.Value.ToUpper;
    if LVal.StartsWith('{$IFDEF') or LVal.StartsWith('{$IFNDEF') or LVal.StartsWith('{$IF') then
    begin
      if LDepth = 0 then
        Result := AStartPos + LMatch.Index - 1;
      Inc(LDepth);
      Continue;
    end;
    
    if LVal.StartsWith('{$ENDIF') or LVal.StartsWith('{$IFEND') then
    begin
      Dec(LDepth);
      if LDepth = 0 then
        Result := ATargetPos;
    end;
  end;
end;

class function TApplyUsesChanges.GetDirectiveBlockEnd(const ASource: string; AStartPos, ATargetPos: Integer): Integer;
var
  LMatches: TMatchCollection;
  LMatch: TMatch;
  LVal: string;
  LDepth: Integer;
begin
  Result := ATargetPos;
  LDepth := GetDirectiveLevel(ASource, AStartPos, ATargetPos);
  if LDepth = 0 then
    Exit;
    
  LMatches := TRegEx.Matches(Copy(ASource, ATargetPos + 1, MaxInt), '\{\$(IFDEF|IFNDEF|IF|ENDIF|IFEND)\b', [roIgnoreCase]);
  for LMatch in LMatches do
  begin
    LVal := LMatch.Value.ToUpper;
    if LVal.StartsWith('{$IFDEF') or LVal.StartsWith('{$IFNDEF') or LVal.StartsWith('{$IF') then
    begin
      Inc(LDepth);
      Continue;
    end;
    
    if LVal.StartsWith('{$ENDIF') or LVal.StartsWith('{$IFEND') then
    begin
      Dec(LDepth);
      if LDepth = 0 then
      begin
        Result := ATargetPos + LMatch.Index + Pos('}', Copy(ASource, ATargetPos + LMatch.Index, MaxInt)) - 1;
        Exit;
      end;
    end;
  end;
end;

class function TApplyUsesChanges.InjectUnconditionalUses(const ASource, AUnitToAdd: string; AWordPos: Integer): string;
begin
  Result := Copy(ASource, 1, AWordPos + 3) + ' ' + AUnitToAdd + ',' + Copy(ASource, AWordPos + 4, MaxInt);
end;

class function TApplyUsesChanges.SanitizeUsesKeyword(const ASource: string; AWordPos, ASemiPos: Integer; out ANewSemiPos: Integer): string;
var
  LTextBetween: string;
begin
  LTextBetween := Copy(ASource, AWordPos + 4, ASemiPos - (AWordPos + 4));
  if TRegEx.IsMatch(LTextBetween, '[a-zA-Z_]') then
  begin
    Result := Copy(ASource, 1, AWordPos - 1) + ',' + Copy(ASource, AWordPos + 4, MaxInt);
    ANewSemiPos := ASemiPos - 3;
    Exit;
  end;
  
  Result := Copy(ASource, 1, AWordPos - 1) + Copy(ASource, AWordPos + 4, MaxInt);
  ANewSemiPos := ASemiPos - 4;
end;

class function TApplyUsesChanges.RelocateSemicolon(const ASource: string; AImplPos, ASemiPos: Integer): string;
var
  LSearchPos: Integer;
begin
  Result := ASource;
  if GetDirectiveLevel(Result, AImplPos, ASemiPos) = 0 then
    Exit;
    
  LSearchPos := GetDirectiveBlockEnd(Result, AImplPos, ASemiPos);
    
  Delete(Result, ASemiPos, 1);
  Insert(';', Result, LSearchPos);
end;

class function TApplyUsesChanges.RewriteConditionalUses(const ASource, AUnitToAdd: string; AImplPos, AWordPos, ASemiPos: Integer): string;
var
  LInsertPos: Integer;
  LNewSemiPos: Integer;
begin
  LInsertPos := GetDirectiveBlockStart(ASource, AImplPos, AWordPos);
    
  Result := SanitizeUsesKeyword(ASource, AWordPos, ASemiPos, LNewSemiPos);
  Result := RelocateSemicolon(Result, AImplPos, LNewSemiPos);
  Insert(sLineBreak + 'uses ' + AUnitToAdd + sLineBreak, Result, LInsertPos);
end;

class function TApplyUsesChanges.AddUnitToUsesClause(const ASource, AUnitToAdd: string; AIsInterface: Boolean): string;
var
  LSectionPos: Integer;
  LUsesPos: Integer;
  LSemiPos: Integer;
  LWordPos: Integer;
  LMatch: TMatch;
  LSectionMatch: TMatch;
  LNextSectionMatch: TMatch;
  LRegex: TRegEx;
  LUsesClauseText: string;
begin
  Result := ASource;
  
  LSectionMatch := TRegEx.Match(ASource, '^\s*implementation\b', [roIgnoreCase, roMultiLine]);
  if AIsInterface then
    LSectionMatch := TRegEx.Match(ASource, '^\s*interface\b', [roIgnoreCase, roMultiLine]);

  if not LSectionMatch.Success then
    Exit;
  LSectionPos := LSectionMatch.Index;

  LRegex := TRegEx.Create('^\s*uses\b', [roIgnoreCase, roMultiLine]);
  LMatch := LRegex.Match(ASource, LSectionPos);
  
  if AIsInterface then
    LNextSectionMatch := TRegEx.Match(ASource, '^\s*implementation\b', [roIgnoreCase, roMultiLine]);

  if (not LMatch.Success) or (AIsInterface and LNextSectionMatch.Success and (LMatch.Index > LNextSectionMatch.Index)) then
  begin
    Result := Copy(ASource, 1, LSectionPos + LSectionMatch.Length - 1) + sLineBreak + 
      'uses' + sLineBreak + '  ' + AUnitToAdd + ';' + 
      Copy(ASource, LSectionPos + LSectionMatch.Length, MaxInt);
    Exit;
  end;
  
  LUsesPos := LMatch.Index;
  LSemiPos := Pos(';', ASource, LUsesPos);
  
  if LSemiPos = 0 then
    Exit;

  LUsesClauseText := Copy(ASource, LUsesPos, LSemiPos - LUsesPos + 1);
  if TRegEx.IsMatch(LUsesClauseText, '(?i)(?<![\w\.])' + TRegEx.Escape(AUnitToAdd) + '(?![\w\.])') then
  begin
    if AIsInterface then
      Exit;

    Result := RemoveUnitSafely(Result, AUnitToAdd);
    LMatch := LRegex.Match(Result, LSectionPos);
    if not LMatch.Success then
      Exit;
      
    LUsesPos := LMatch.Index;
    LSemiPos := Pos(';', Result, LUsesPos);
  end;
  
  LWordPos := LUsesPos + LMatch.Length - 4; 
  if GetDirectiveLevel(Result, LSectionPos, LWordPos) = 0 then
  begin
    Result := InjectUnconditionalUses(Result, AUnitToAdd, LWordPos);
    Exit;
  end;
  
  Result := RewriteConditionalUses(Result, AUnitToAdd, LSectionPos, LWordPos, LSemiPos);
end;

class function TApplyUsesChanges.AddUnitToImplementationUses(const ASource, AUnitToAdd: string): string;
begin
  Result := AddUnitToUsesClause(ASource, AUnitToAdd, False);
end;

class function TApplyUsesChanges.AddUnitToInterfaceUses(const ASource, AUnitToAdd: string): string;
begin
  Result := AddUnitToUsesClause(ASource, AUnitToAdd, True);
end;

procedure TApplyUsesChanges.Execute(const AFilePath: string; const AAnalysisResult: TUnitAnalysisResult);
var
  LContent: string;
  LUnit: string;
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

