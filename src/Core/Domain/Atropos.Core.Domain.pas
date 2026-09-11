unit Atropos.Core.Domain;

interface
uses
  System.Generics.Collections,
  Atropos.Core.Ports, Atropos.Core.Analysis, Atropos.Core.Effects, System.SysUtils;

type
  
  TUnitExports = class
  public
    UnitName: string;
    ExportedIdentifiers: TList<string>;
    ExportedHelpers: TObjectDictionary<string, TList<string>>;
    HasInitialization: Boolean;
    Imports: TArray<string>;
    ImportsKnown: Boolean;
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
    FEffects: TUnitEffectGraph;
    function LoadEffectFacts(const AUnitName: string): TUnitEffectFacts;
    procedure LoadResolverImports(const AUnitName: string);
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
    function FindUnitAmbiguity(const AUnitName: string;
      const AVisibleUnits, AIdentifiers: TArray<string>): string;
    function HasUnit(const AUnitName: string): Boolean;
    function UnitHasInitialization(const AUnitName: string): Boolean;
    procedure RegisterUnitDependencies(const AUnitName: string; const AImports: TArray<string>;
      AKnown: Boolean = True);
    function AssessUnitEffects(const AUnitName: string): TEffectAssessment;
  end;

  TUnitAnalysisResult = record
    UnitName: string;
    UnusedUnits: TArray<string>;
    UnitsToMoveToImpl: TArray<string>;
    PreservedAmbiguities: TArray<string>;
    Decisions: TArray<TDependencyDecision>;
    PreservationReasons: TArray<string>;
  end;
  
  TAnalyzeUnitUses = class
  private
    FLogger: ILogger;
    function IsUnitUsed(AContext: TProjectContext; const AUnitName: string;
      const AUsedIdentifiers, AVisibleIdentifiers: TArray<string>): Boolean;
    function MustPreserve(AContext: TProjectContext; const AUnitName: string;
      ASection: TUsesSection; const AVisibleUnits, AIdentifiers: TArray<string>;
      ADecisions: TDependencyDecisions): Boolean;
    function PreserveIncomplete(const ASyntaxTree: IUnitSyntaxTree;
      ADecisions: TDependencyDecisions; var AResult: TUnitAnalysisResult): Boolean;
    function PreserveConstrainedImport(const ATree: IUnitSyntaxTree;
      const AName: string; ASection: TUsesSection; ADecisions: TDependencyDecisions): Boolean;
  public
    constructor Create(ALogger: ILogger = nil);
    function Execute(const ASyntaxTree: IUnitSyntaxTree; AContext: TProjectContext): TUnitAnalysisResult;
  end;

implementation

constructor TUnitExports.Create(const AUnitName: string; AHasInit: Boolean = False; AIsNative: Boolean = False);
begin
  UnitName := AUnitName;
  HasInitialization := AHasInit;
  ImportsKnown := False;
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
  FEffects := TUnitEffectGraph.Create;
  FUnitExports := TObjectDictionary<string, TUnitExports>.Create([doOwnsValues]);
  FMissingUnits := TDictionary<string, Boolean>.Create;
  FResolver := AResolver;
  FLogger := ALogger;
end;

destructor TProjectContext.Destroy;
begin
  FEffects.Free;
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
      LoadResolverImports(AUnitName);
      Exit(True);
    end;
    
    FMissingUnits.Add(LLowerName, True);
  end;
end;

procedure TProjectContext.RegisterUnitDependencies(const AUnitName: string;
  const AImports: TArray<string>; AKnown: Boolean);
var LExports: TUnitExports;
begin
  LExports := FUnitExports[AUnitName.ToLower];
  LExports.Imports := Copy(AImports);
  LExports.ImportsKnown := AKnown;
end;

procedure TProjectContext.LoadResolverImports(const AUnitName: string);
var LDependencies: IUnitDependencyResolver; LImports: TArray<string>; LKnown: Boolean;
begin
  LKnown := False;
  if Supports(FResolver, IUnitDependencyResolver, LDependencies) then
    LKnown := LDependencies.TryGetUnitImports(AUnitName, LImports);
  RegisterUnitDependencies(AUnitName, LImports, LKnown);
end;

function TProjectContext.LoadEffectFacts(const AUnitName: string): TUnitEffectFacts;
var LExports: TUnitExports;
begin
  Result := Default(TUnitEffectFacts);
  if not HasUnit(AUnitName) then
    Exit;
  LExports := FUnitExports[AUnitName.ToLower];
  Result.DirectEffects := LExports.HasInitialization;
  Result.ImportsKnown := LExports.ImportsKnown;
  Result.Imports := LExports.Imports;
end;

function TProjectContext.AssessUnitEffects(const AUnitName: string): TEffectAssessment;
begin
  Result := FEffects.Assess(AUnitName,
    function(const AName: string): TUnitEffectFacts
    begin Result := LoadEffectFacts(AName) end);
end;
function TProjectContext.UnitHasInitialization(const AUnitName: string): Boolean;
var
  LExports: TUnitExports;
begin
  Result := False;
  if not FUnitExports.TryGetValue(AUnitName.ToLower, LExports) then
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

function TProjectContext.FindUnitAmbiguity(const AUnitName: string;
  const AVisibleUnits, AIdentifiers: TArray<string>): string;
var
  LIdentifier: string;
  LCandidate: string;
  LCandidates: TArray<string>;
  LQualifiedUnit: string;
  LBaseIdentifier: string;
begin
  Result := EmptyStr;
  for LIdentifier in AIdentifiers do
  begin
    if TryResolveQualifiedUnit(LIdentifier, LQualifiedUnit, LBaseIdentifier) then
      Continue;
    LCandidates := FindExportingUnits(LIdentifier, AVisibleUnits);
    if Length(LCandidates) < 2 then
      Continue;
    for LCandidate in LCandidates do
    begin
      if SameText(LCandidate, AUnitName) then
        Exit(Format('%s is exported by %s', [LIdentifier,
          string.Join(', ', LCandidates)]));
    end;
  end;
end;

constructor TAnalyzeUnitUses.Create(ALogger: ILogger = nil);
begin
  FLogger := ALogger;
end;

function TAnalyzeUnitUses.IsUnitUsed(AContext: TProjectContext;
  const AUnitName: string; const AUsedIdentifiers,
  AVisibleIdentifiers: TArray<string>): Boolean;
var
  LIdent: string;
begin
  Result := False;
  for LIdent in AUsedIdentifiers do
  begin
    if AContext.UnitExportsIdentifier(AUnitName, LIdent,
      AVisibleIdentifiers) then
    begin
      if Assigned(FLogger) then
        FLogger.Log(Format('DEBUG-MATCH: [%s] matched with exported identifier [%s]', [AUnitName, LIdent]));
      Exit(True);
    end;
  end;
end;

function TAnalyzeUnitUses.MustPreserve(AContext: TProjectContext;
  const AUnitName: string; ASection: TUsesSection;
  const AVisibleUnits, AIdentifiers: TArray<string>;
  ADecisions: TDependencyDecisions): Boolean;
var
  LReason: string;
  LEffects: TEffectAssessment;
begin
  Result := True;
  if not AContext.HasUnit(AUnitName) then
  begin
    ADecisions.Add(TDependencyDecision.Create(AUnitName, ASection, dsUnknown,
      daPreserve, 'Source or exports could not be resolved.'));
    Exit;
  end;
  LEffects := AContext.AssessUnitEffects(AUnitName);
  if LEffects.State = esUnknown then
  begin
    ADecisions.Add(TDependencyDecision.Create(AUnitName, ASection, dsUnknown,
      daPreserve, LEffects.Reason));
    Exit;
  end;
  if LEffects.State = esPresent then
  begin
    ADecisions.Add(TDependencyDecision.Create(AUnitName, ASection, dsUsed,
      daPreserve, LEffects.Reason));
    Exit;
  end;
  LReason := AContext.FindUnitAmbiguity(AUnitName, AVisibleUnits, AIdentifiers);
  if not LReason.IsEmpty then
  begin
    ADecisions.Add(TDependencyDecision.Create(AUnitName, ASection, dsAmbiguous,
      daPreserve, LReason));
    Exit;
  end;
  Result := False;
end;

function TAnalyzeUnitUses.PreserveIncomplete(const ASyntaxTree: IUnitSyntaxTree;
  ADecisions: TDependencyDecisions; var AResult: TUnitAnalysisResult): Boolean;
var
  LDiagnostics: IUnitAnalysisDiagnostics;
  LReasons: TArray<string>;
  LReason: string;
  LUnitName: string;
begin
  Result := False;
  if not Supports(ASyntaxTree, IUnitAnalysisDiagnostics, LDiagnostics) then
    Exit;
  LReasons := LDiagnostics.GetIncompleteAnalysisReasons;
  if Length(LReasons) = 0 then
    Exit;
  LReason := string.Join('; ', LReasons);
  for LUnitName in ASyntaxTree.GetInterfaceUses do
    ADecisions.Add(TDependencyDecision.Create(LUnitName, usInterface,
      dsUnknown, daPreserve, LReason));
  for LUnitName in ASyntaxTree.GetImplementationUses do
    ADecisions.Add(TDependencyDecision.Create(LUnitName, usImplementation,
      dsUnknown, daPreserve, LReason));
  AResult.Decisions := ADecisions.ToArray;
  AResult.PreservationReasons := ['unknown analysis: ' + LReason];
  Result := True;
end;

function TAnalyzeUnitUses.PreserveConstrainedImport(const ATree: IUnitSyntaxTree;
  const AName: string; ASection: TUsesSection; ADecisions: TDependencyDecisions): Boolean;
var
  LConstraints: IUnitImportConstraints;
  LName: string;
begin
  Result := False;
  if not Supports(ATree, IUnitImportConstraints, LConstraints) then
    Exit;
  for LName in LConstraints.GetPreservedImportNames do
  begin
    if not SameText(LName, AName) then
      Continue;
    ADecisions.Add(TDependencyDecision.Create(AName, ASection, dsUnknown, daPreserve,
      'Conditional import requires occurrence-aware editing.'));
    Exit(True);
  end;
end;

function TAnalyzeUnitUses.Execute(const ASyntaxTree: IUnitSyntaxTree; AContext: TProjectContext): TUnitAnalysisResult;
var
  LIntfUses: TArray<string>;
  LImplUses: TArray<string>;
  LIntfIdents: TArray<string>;
  LImplIdents: TArray<string>;
  LDecisions: TDependencyDecisions;
  LAmbiguities: TList<string>;
  LUnitName: string;
  LUsedInIntf: Boolean;
  LUsedInImpl: Boolean;
begin
  Result := Default(TUnitAnalysisResult);
  Result.UnitName := ASyntaxTree.GetUnitName;
  LDecisions := TDependencyDecisions.Create;
  LAmbiguities := TList<string>.Create;
  try
    if PreserveIncomplete(ASyntaxTree, LDecisions, Result) then
      Exit;
    LIntfUses := ASyntaxTree.GetInterfaceUses;
    LImplUses := ASyntaxTree.GetImplementationUses;
    LIntfIdents := ASyntaxTree.GetIdentifiersUsedInInterface;
    LImplIdents := ASyntaxTree.GetIdentifiersUsedInImplementation;

    LAmbiguities.AddRange(AContext.FindAmbiguities(LIntfUses, LIntfIdents));
    LAmbiguities.AddRange(AContext.FindAmbiguities(LIntfUses + LImplUses, LImplIdents));

    for LUnitName in LIntfUses do
    begin
      if PreserveConstrainedImport(ASyntaxTree, LUnitName, usInterface, LDecisions) then
        Continue;
      if MustPreserve(AContext, LUnitName, usInterface,
        LIntfUses, LIntfIdents, LDecisions) then
        Continue;

      LUsedInIntf := IsUnitUsed(AContext, LUnitName, LIntfIdents,
        LIntfIdents);
      if LUsedInIntf then
      begin
        LDecisions.Add(TDependencyDecision.Create(LUnitName, usInterface,
          dsUsed, daPreserve, 'Matching identifier in the interface.'));
        Continue;
      end;

      if MustPreserve(AContext, LUnitName, usInterface,
        LIntfUses + LImplUses, LImplIdents, LDecisions) then
        Continue;
      LUsedInImpl := IsUnitUsed(AContext, LUnitName, LImplIdents,
        LIntfIdents + LImplIdents);
      
      if LUsedInImpl then
      begin
        LDecisions.Add(TDependencyDecision.Create(LUnitName, usInterface,
          dsUsed, daMoveToImplementation, 'Matching identifier only in the implementation.'));
        Continue;
      end;
      
      LDecisions.Add(TDependencyDecision.Create(LUnitName, usInterface,
        dsUnused, daRemove, 'No matching identifier in the current syntax analysis.'));
    end;

    for LUnitName in LImplUses do
    begin
      if PreserveConstrainedImport(ASyntaxTree, LUnitName, usImplementation, LDecisions) then
        Continue;
      if MustPreserve(AContext, LUnitName, usImplementation,
        LIntfUses + LImplUses, LImplIdents, LDecisions) then
        Continue;

      LUsedInImpl := IsUnitUsed(AContext, LUnitName, LImplIdents,
        LIntfIdents + LImplIdents);
      
      if not LUsedInImpl then
      begin
        LDecisions.Add(TDependencyDecision.Create(LUnitName, usImplementation,
          dsUnused, daRemove, 'No matching identifier in the implementation.'));
        Continue;
      end;
      LDecisions.Add(TDependencyDecision.Create(LUnitName, usImplementation,
        dsUsed, daPreserve, 'Matching identifier in the implementation.'));
    end;

    Result.UnusedUnits := LDecisions.UnitsForAction(daRemove);
    Result.UnitsToMoveToImpl := LDecisions.UnitsForAction(daMoveToImplementation);
    Result.Decisions := LDecisions.ToArray;
    Result.PreservationReasons := LDecisions.PreservationMessages;
    Result.PreservedAmbiguities := LAmbiguities.ToArray;
  finally
    LAmbiguities.Free;
    LDecisions.Free;
  end;
end;

end.

