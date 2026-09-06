unit Atropos.Core.Domain;

interface
uses
  System.Generics.Collections,
  Atropos.Core.Ports, System.SysUtils;

type
  
  TUnitExports = class
  public
    UnitName: string;
    ExportedIdentifiers: TList<string>;
    ExportedHelpers: TObjectDictionary<string, TList<string>>;
    HasInitialization: Boolean;
    IsNative: Boolean;
    constructor Create(const AUnitName: string; AHasInit: Boolean = False; AIsNative: Boolean = False);
    destructor Destroy; override;
  end;
  
  TProjectContext = class
  private
    FUnitExports: TObjectDictionary<string, TUnitExports>;
    FMissingUnits: TDictionary<string, Boolean>;
    FResolver: IExternalUnitResolver;
    FLogger: ILogger;
    function TryResolveQualifiedUnit(const AIdentifier: string;
      out AUnitName, ABaseIdentifier: string): Boolean;
    function FindExportingUnits(const AIdentifier: string;
      const AVisibleUnits: TArray<string>): TArray<string>;
  public
    constructor Create(AResolver: IExternalUnitResolver = nil; ALogger: ILogger = nil);
    destructor Destroy; override;
    procedure RegisterUnitExports(const AUnitName: string; const AIdentifiers: TArray<string>; AHasInit: Boolean = False; AIsNative: Boolean = False);
    function UnitExportsIdentifier(const AUnitName, AIdentifier: string; const AAllUsedIdents: TArray<string>): Boolean;
    function FindAmbiguities(const AVisibleUnits,
      AIdentifiers: TArray<string>): TArray<string>;
    function HasUnit(const AUnitName: string): Boolean;
    function UnitHasInitialization(const AUnitName: string): Boolean;
  end;

  TUnitAnalysisResult = record
    UnitName: string;
    UnusedUnits: TArray<string>;
    UnitsToMoveToImpl: TArray<string>;
    PreservedAmbiguities: TArray<string>;
  end;
  
  TAnalyzeUnitUses = class
  private
    FLogger: ILogger;
    function IsUnitUsed(AContext: TProjectContext; const AUnitName: string; const AIdents: TArray<string>): Boolean;
  public
    constructor Create(ALogger: ILogger = nil);
    function Execute(const ASyntaxTree: IUnitSyntaxTree; AContext: TProjectContext): TUnitAnalysisResult;
  end;

implementation

constructor TUnitExports.Create(const AUnitName: string; AHasInit: Boolean = False; AIsNative: Boolean = False);
begin
  UnitName := AUnitName;
  HasInitialization := AHasInit;
  IsNative := AIsNative;
  ExportedIdentifiers := TList<string>.Create;
  ExportedHelpers := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
end;

destructor TUnitExports.Destroy;
begin
  ExportedHelpers.Free;
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

procedure TProjectContext.RegisterUnitExports(const AUnitName: string; const AIdentifiers: TArray<string>; AHasInit: Boolean = False; AIsNative: Boolean = False);
var
  LExports: TUnitExports;
  LIdent: string;
  LParts: TArray<string>;
  LMethod, LTarget: string;
  LList: TList<string>;
begin
  LExports := TUnitExports.Create(AUnitName, AHasInit, AIsNative);
  for LIdent in AIdentifiers do
  begin
    if not LIdent.StartsWith('!HELPER:') then
    begin
      LExports.ExportedIdentifiers.Add(LIdent.ToLower);
      Continue;
    end;
    LParts := LIdent.Split([':']);
    if Length(LParts) < 3 then
      Continue;
    LMethod := LParts[1].ToLower;
    LTarget := LParts[2].ToLower;
    if not LExports.ExportedHelpers.TryGetValue(LMethod, LList) then
    begin
      LList := TList<string>.Create;
      LExports.ExportedHelpers.Add(LMethod, LList);
    end;
    if not LList.Contains(LTarget) then
      LList.Add(LTarget);
  end;
  FUnitExports.AddOrSetValue(AUnitName.ToLower, LExports);
end;

function TProjectContext.HasUnit(const AUnitName: string): Boolean;
var
  LLowerName: string;
  LExports: TArray<string>;
  LHasInit: Boolean;
  LIsNative: Boolean;
begin
  LLowerName := AUnitName.ToLower;
  Result := FUnitExports.ContainsKey(LLowerName);
  
  if (not Result) and Assigned(FResolver) and not FMissingUnits.ContainsKey(LLowerName) then
  begin
    if FResolver.TryResolveUnit(AUnitName, LExports, LHasInit, LIsNative) then
    begin
      RegisterUnitExports(AUnitName, LExports, LHasInit, LIsNative);
      Exit(True);
    end;
    
    FMissingUnits.Add(LLowerName, True);
  end;
end;

function TProjectContext.UnitHasInitialization(const AUnitName: string): Boolean;
var
  LExports: TUnitExports;
begin
  Result := False;
  if not FUnitExports.TryGetValue(AUnitName.ToLower, LExports) then
    Exit;
  if LExports.IsNative then
    Exit;
  Result := LExports.HasInitialization;
end;

function TProjectContext.UnitExportsIdentifier(const AUnitName, AIdentifier: string; const AAllUsedIdents: TArray<string>): Boolean;
var
  LExports: TUnitExports;
  LBaseIdent: string;
  LPos: Integer;
  LTargetTypes: TList<string>;
  LTarget: string;
  LUsedLower: string;
  LQualifiedUnit: string;
  LQualifiedBaseIdentifier: string;
begin
  Result := False;
  if FUnitExports.TryGetValue(LowerCase(AUnitName), LExports) then
  begin
    LBaseIdent := LowerCase(AIdentifier);

    if TryResolveQualifiedUnit(AIdentifier, LQualifiedUnit,
      LQualifiedBaseIdentifier) then
    begin
      if not SameText(LQualifiedUnit, AUnitName) then
        Exit;
      LBaseIdent := LowerCase(LQualifiedBaseIdentifier);
    end;
    
    // Remover argumentos genéricos (ex: TArray<string> -> tarray)
    LPos := Pos('<', LBaseIdent);
    if LPos > 0 then
      LBaseIdent := Copy(LBaseIdent, 1, LPos - 1);
      
    // Remover prefixos de namespace/unit (ex: SysUtils.Exception -> exception)
    LPos := LastDelimiter('.', LBaseIdent);
    if LPos > 0 then
      LBaseIdent := Copy(LBaseIdent, LPos + 1, MaxInt);
      
    Result := LExports.ExportedIdentifiers.Contains(LBaseIdent);
    
    if not Result then
    begin
      if LExports.ExportedHelpers.TryGetValue(LBaseIdent, LTargetTypes) then
      begin
        for LTarget in LTargetTypes do
        begin
          if (LTarget = 'string') or (LTarget = 'integer') or (LTarget = 'tobject') then
            Exit(True);
            
          for LUsedLower in AAllUsedIdents do
          begin
            if LowerCase(LUsedLower) = LTarget then
              Exit(True);
          end;
        end;
      end;
    end;
  end;
end;

function TProjectContext.TryResolveQualifiedUnit(const AIdentifier: string;
  out AUnitName, ABaseIdentifier: string): Boolean;
var
  LRegisteredUnit: string;
  LLowerIdentifier: string;
  LPrefix: string;
begin
  Result := False;
  AUnitName := EmptyStr;
  ABaseIdentifier := AIdentifier;
  LLowerIdentifier := LowerCase(AIdentifier);
  for LRegisteredUnit in FUnitExports.Keys do
  begin
    LPrefix := LRegisteredUnit + '.';
    if not LLowerIdentifier.StartsWith(LPrefix) then
      Continue;
    if Length(LRegisteredUnit) <= Length(AUnitName) then
      Continue;
    AUnitName := LRegisteredUnit;
    ABaseIdentifier := Copy(AIdentifier, Length(LPrefix) + 1, MaxInt);
    Result := True;
  end;
end;

function TProjectContext.FindExportingUnits(const AIdentifier: string;
  const AVisibleUnits: TArray<string>): TArray<string>;
var
  LUnitName: string;
  LMatches: TList<string>;
begin
  LMatches := TList<string>.Create;
  try
    for LUnitName in AVisibleUnits do
    begin
      if not HasUnit(LUnitName) then
        Continue;
      if not UnitExportsIdentifier(LUnitName, AIdentifier, []) then
        Continue;
      LMatches.Add(LUnitName);
    end;
    Result := LMatches.ToArray;
  finally
    LMatches.Free;
  end;
end;

function TProjectContext.FindAmbiguities(const AVisibleUnits,
  AIdentifiers: TArray<string>): TArray<string>;
var
  LIdentifier: string;
  LVisibleUnit: string;
  LQualifiedUnit: string;
  LBaseIdentifier: string;
  LExportingUnits: TArray<string>;
  LAmbiguities: TList<string>;
begin
  LAmbiguities := TList<string>.Create;
  try
    for LVisibleUnit in AVisibleUnits do
      HasUnit(LVisibleUnit);
    for LIdentifier in AIdentifiers do
    begin
      if TryResolveQualifiedUnit(LIdentifier, LQualifiedUnit,
        LBaseIdentifier) then
        Continue;
      LExportingUnits := FindExportingUnits(LIdentifier, AVisibleUnits);
      if Length(LExportingUnits) < 2 then
        Continue;
      LBaseIdentifier := Format('%s is exported by %s', [LIdentifier,
        string.Join(', ', LExportingUnits)]);
      if LAmbiguities.Contains(LBaseIdentifier) then
        Continue;
      LAmbiguities.Add(LBaseIdentifier);
    end;
    Result := LAmbiguities.ToArray;
  finally
    LAmbiguities.Free;
  end;
end;

constructor TAnalyzeUnitUses.Create(ALogger: ILogger = nil);
begin
  FLogger := ALogger;
end;

function TAnalyzeUnitUses.IsUnitUsed(AContext: TProjectContext; const AUnitName: string; const AIdents: TArray<string>): Boolean;
var
  LIdent: string;
begin
  Result := False;
  for LIdent in AIdents do
  begin
    if AContext.UnitExportsIdentifier(AUnitName, LIdent, AIdents) then
    begin
      if Assigned(FLogger) then
        FLogger.Log(Format('DEBUG-MATCH: [%s] matched with exported identifier [%s]', [AUnitName, LIdent]));
      Exit(True);
    end;
  end;
end;

function TAnalyzeUnitUses.Execute(const ASyntaxTree: IUnitSyntaxTree; AContext: TProjectContext): TUnitAnalysisResult;
var
  LIntfUses: TArray<string>;
  LImplUses: TArray<string>;
  LIntfIdents: TArray<string>;
  LImplIdents: TArray<string>;
  LUnused: TList<string>;
  LMoved: TList<string>;
  LAmbiguities: TList<string>;
  LUnitName: string;
  LUsedInIntf: Boolean;
  LUsedInImpl: Boolean;
begin
  Result.UnitName := ASyntaxTree.GetUnitName;
  LUnused := TList<string>.Create;
  LMoved := TList<string>.Create;
  LAmbiguities := TList<string>.Create;
  try
    LIntfUses := ASyntaxTree.GetInterfaceUses;
    LImplUses := ASyntaxTree.GetImplementationUses;
    LIntfIdents := ASyntaxTree.GetIdentifiersUsedInInterface;
    LImplIdents := ASyntaxTree.GetIdentifiersUsedInImplementation;

    LAmbiguities.AddRange(AContext.FindAmbiguities(LIntfUses, LIntfIdents));
    LAmbiguities.AddRange(AContext.FindAmbiguities(LImplUses, LImplIdents));

    for LUnitName in LIntfUses do
    begin
      if not AContext.HasUnit(LUnitName) then
        Continue;

      if AContext.UnitHasInitialization(LUnitName) then
        Continue;

      LUsedInIntf := IsUnitUsed(AContext, LUnitName, LIntfIdents);
      if LUsedInIntf then
        Continue;

      LUsedInImpl := IsUnitUsed(AContext, LUnitName, LImplIdents);
      
      if LUsedInImpl then
      begin
        LMoved.Add(LUnitName);
        Continue;
      end;
      
      LUnused.Add(LUnitName);
    end;

    for LUnitName in LImplUses do
    begin
      if not AContext.HasUnit(LUnitName) then
        Continue;

      if AContext.UnitHasInitialization(LUnitName) then
        Continue;

      LUsedInImpl := IsUnitUsed(AContext, LUnitName, LImplIdents);
      
      if not LUsedInImpl then
        LUnused.Add(LUnitName);
    end;

    Result.UnusedUnits := LUnused.ToArray;
    Result.UnitsToMoveToImpl := LMoved.ToArray;
    Result.PreservedAmbiguities := LAmbiguities.ToArray;
  finally
    LAmbiguities.Free;
    LUnused.Free;
    LMoved.Free;
  end;
end;

end.

