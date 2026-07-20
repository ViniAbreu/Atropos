unit Atropos.Core.Domain;

interface
uses
  System.Generics.Collections, Atropos.Core.Ports;

type
  
  TUnitExports = class
  public
    UnitName: string;
    ExportedIdentifiers: TList<string>;
    constructor Create(const AUnitName: string);
    destructor Destroy; override;
  end;

  
  TProjectContext = class
  private
    FUnitExports: TObjectDictionary<string, TUnitExports>;
    FMissingUnits: TDictionary<string, Boolean>;
    FResolver: IExternalUnitResolver;
    FLogger: ILogger;
  public
    constructor Create(AResolver: IExternalUnitResolver = nil; ALogger: ILogger = nil);
    destructor Destroy; override;
    procedure RegisterUnitExports(const AUnitName: string; const AIdentifiers: TArray<string>);
    function UnitExportsIdentifier(const AUnitName, AIdentifier: string): Boolean;
    function HasUnit(const AUnitName: string): Boolean;
  end;

  
  TUnitAnalysisResult = record
    UnitName: string;
    UnusedUnits: TArray<string>;
    UnitsToMoveToImpl: TArray<string>;
  end;

  
  TAnalyzeUnitUses = class
  private
    FLogger: ILogger;
  public
    constructor Create(ALogger: ILogger = nil);
    function Execute(const ASyntaxTree: IUnitSyntaxTree; AContext: TProjectContext): TUnitAnalysisResult;
  end;

implementation
uses
  System.SysUtils;



constructor TUnitExports.Create(const AUnitName: string);
begin
  UnitName := AUnitName;
  ExportedIdentifiers := TList<string>.Create;
end;

destructor TUnitExports.Destroy;
begin
  ExportedIdentifiers.Free;
  inherited;
end;



constructor TProjectContext.Create(AResolver: IExternalUnitResolver = nil; ALogger: ILogger = nil);
begin
  FUnitExports := TObjectDictionary<string, TUnitExports>.Create([doOwnsValues]);
  FMissingUnits := TDictionary<string, Boolean>.Create;
  FResolver := AResolver;
  FLogger := ALogger;
end;

destructor TProjectContext.Destroy;
begin
  FMissingUnits.Free;
  FUnitExports.Free;
  inherited;
end;

procedure TProjectContext.RegisterUnitExports(const AUnitName: string; const AIdentifiers: TArray<string>);
var
  LExports: TUnitExports;
  LIdent: string;
begin
  LExports := TUnitExports.Create(AUnitName);
  for LIdent in AIdentifiers do
    LExports.ExportedIdentifiers.Add(LowerCase(LIdent));
  FUnitExports.AddOrSetValue(LowerCase(AUnitName), LExports);
end;

function TProjectContext.HasUnit(const AUnitName: string): Boolean;
var
  LLowerName: string;
  LExports: TArray<string>;
begin
  LLowerName := LowerCase(AUnitName);
  Result := FUnitExports.ContainsKey(LLowerName);
  
  if (not Result) and Assigned(FResolver) and not FMissingUnits.ContainsKey(LLowerName) then
  begin
    if FResolver.TryResolveUnit(AUnitName, LExports) then
    begin
      RegisterUnitExports(AUnitName, LExports);
      Result := True;
    end
    else
      FMissingUnits.Add(LLowerName, True);
  end;
end;

function TProjectContext.UnitExportsIdentifier(const AUnitName, AIdentifier: string): Boolean;
var
  LExports: TUnitExports;
  LBaseIdent: string;
  LPos: Integer;
  LPrefix: string;
begin
  Result := False;
  if FUnitExports.TryGetValue(LowerCase(AUnitName), LExports) then
  begin
    LBaseIdent := LowerCase(AIdentifier);

    
    LPos := Pos('<', LBaseIdent);
    if LPos > 0 then
    begin
      LBaseIdent := Copy(LBaseIdent, 1, LPos - 1);
    end;
      
    
    LPos := LastDelimiter('.', LBaseIdent);
    if LPos > 0 then
    begin
      LPrefix := Copy(LBaseIdent, 1, LPos - 1);
      
      if not LowerCase(AUnitName).EndsWith(LPrefix) then
        Exit(False);
        
      LBaseIdent := Copy(LBaseIdent, LPos + 1, MaxInt);
    end;
    
    
    
    
    if LPrefix = '' then
    begin
      if (LBaseIdent = 'tlist') and (LowerCase(AUnitName) = 'system.classes') then
        Exit(False);
      if (LBaseIdent = 'tqueue') and (LowerCase(AUnitName) = 'system.contnrs') then
        Exit(False);
      if (LBaseIdent = 'tstack') and (LowerCase(AUnitName) = 'system.contnrs') then
        Exit(False);
    end;
      
    Result := LExports.ExportedIdentifiers.Contains(LBaseIdent);
    if Result and (LowerCase(AUnitName) = 'system.classes') then
      if Assigned(FLogger) then FLogger.Log('DEBUG IDENT MATCH: System.Classes matched ' + LBaseIdent + ' from original ' + AIdentifier);
  end;
end;



constructor TAnalyzeUnitUses.Create(ALogger: ILogger = nil);
begin
  FLogger := ALogger;
end;

function TAnalyzeUnitUses.Execute(const ASyntaxTree: IUnitSyntaxTree; AContext: TProjectContext): TUnitAnalysisResult;
var
  LIntfUses, LImplUses: TArray<string>;
  LIntfIdents, LImplIdents: TArray<string>;
  LUnused, LMoved: TList<string>;
  LUnitName, LIdent: string;
  LUsedInIntf, LUsedInImpl: Boolean;
begin
  Result.UnitName := ASyntaxTree.GetUnitName;
  LUnused := TList<string>.Create;
  LMoved := TList<string>.Create;
  try
    LIntfUses := ASyntaxTree.GetInterfaceUses;
    LImplUses := ASyntaxTree.GetImplementationUses;
    LIntfIdents := ASyntaxTree.GetIdentifiersUsedInInterface;
    LImplIdents := ASyntaxTree.GetIdentifiersUsedInImplementation;

    
    for LUnitName in LIntfUses do
    begin
      if not AContext.HasUnit(LUnitName) then
        Continue;

      LUsedInIntf := False;
      LUsedInImpl := False;

      for LIdent in LIntfIdents do
        if AContext.UnitExportsIdentifier(LUnitName, LIdent) then
        begin
          LUsedInIntf := True;
          Break;
        end;

      if not LUsedInIntf then
      begin
        for LIdent in LImplIdents do
          if AContext.UnitExportsIdentifier(LUnitName, LIdent) then
          begin
            LUsedInImpl := True;
            Break;
          end;

        if Assigned(FLogger) then FLogger.Log('DEBUG: ' + LUnitName + ' UsedInImpl: ' + BoolToStr(LUsedInImpl, True));
        if LUsedInImpl then
          LMoved.Add(LUnitName)
        else
          LUnused.Add(LUnitName);
      end
      else
        if Assigned(FLogger) then FLogger.Log('DEBUG: ' + LUnitName + ' UsedInIntf: True');
    end;

    
    for LUnitName in LImplUses do
    begin
      if not AContext.HasUnit(LUnitName) then
        Continue;

      LUsedInImpl := False;
      for LIdent in LImplIdents do
        if AContext.UnitExportsIdentifier(LUnitName, LIdent) then
        begin
          LUsedInImpl := True;
          Break;
        end;
      
      if Assigned(FLogger) then FLogger.Log('DEBUG: ' + LUnitName + ' UsedInImpl: ' + BoolToStr(LUsedInImpl, True));
      
      if not LUsedInImpl then
        LUnused.Add(LUnitName);
    end;

    Result.UnusedUnits := LUnused.ToArray;
    Result.UnitsToMoveToImpl := LMoved.ToArray;
  finally
    LUnused.Free;
    LMoved.Free;
  end;
end;

end.

