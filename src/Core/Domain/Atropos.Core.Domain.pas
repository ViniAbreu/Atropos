unit Atropos.Core.Domain;

interface
uses
  System.Generics.Collections,
  Atropos.Core.LocalBinding, Atropos.Core.UnitSymbols, Atropos.Core.HelperBinding, Atropos.Core.Ports, Atropos.Core.Analysis, Atropos.Core.Effects, System.SysUtils;

type
  
  TUnitExports = Atropos.Core.UnitSymbols.TUnitExports;
  
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
    function UnitExportsIdentifier(const AUnitName, AIdentifier: string;
      const AAllUsedIdents: TArray<string>; AIncludeHelpers: Boolean = True;
      AStructured: Boolean = False): Boolean;
    function AssessHelpers(const AUnitName: string; const AVisibleUnits: TArray<string>;
      const AReferences: TArray<TMemberReference>; AKnown, AInterface: Boolean): THelperUse;
    function FindAmbiguities(const AVisibleUnits,
      AIdentifiers: TArray<string>): TArray<string>;
    function FindUnitAmbiguity(const AUnitName: string;
      const AVisibleUnits, AIdentifiers: TArray<string>): string;
    function HasUnit(const AUnitName: string): Boolean;
    function UnitHasInitialization(const AUnitName: string): Boolean;
    procedure RegisterUnitDependencies(const AUnitName: string; const AImports: TArray<string>;
      AKnown: Boolean = True);
    function AssessUnitEffects(const AUnitName: string): TEffectAssessment;
    procedure RegisterImplicitEffects(const AUnitName: string;
      const AEffects: TArray<TImplicitEffect>; AKnown: Boolean = True);
    procedure RegisterExportFacts(const AUnitName: string; const AFacts: TArray<TExportedSymbol>);
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
    FReferences: TArray<TMemberReference>;
    FReferencesKnown, FReferenceInterface: Boolean;
    FHelperUse: THelperUse;
    FUnknownReferences: array[Boolean] of TArray<string>;
    procedure InitializeFacts(const ATree: IUnitSyntaxTree);
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

uses Atropos.Core.TypeNames;

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

procedure TProjectContext.RegisterUnitExports(const AUnitName: string;
  const AIdentifiers: TArray<string>; AHasInit: Boolean; AIsNative: Boolean);
var LExports: TUnitExports;
begin
  LExports := TUnitExports.Create(AUnitName, AHasInit, AIsNative);
  LExports.AddIdentifiers(AIdentifiers);
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
  LResolver: IUnitImplicitEffectResolver; LEffects: TArray<TImplicitEffect>;
  LExports: IUnitExportFactResolver; LFacts: TArray<TExportedSymbol>;
begin
  LKnown := False;
  if Supports(FResolver, IUnitDependencyResolver, LDependencies) then
    LKnown := LDependencies.TryGetUnitImports(AUnitName, LImports);
  RegisterUnitDependencies(AUnitName, LImports, LKnown);
  LKnown := False;
  if Supports(FResolver, IUnitImplicitEffectResolver, LResolver) then
    LKnown := LResolver.TryGetImplicitEffects(AUnitName, LEffects);
  RegisterImplicitEffects(AUnitName, LEffects, LKnown);
  if Supports(FResolver, IUnitExportFactResolver, LExports) then
    if LExports.TryGetExportFacts(AUnitName, LFacts) then
      RegisterExportFacts(AUnitName, LFacts);
end;

procedure TProjectContext.RegisterExportFacts(const AUnitName: string;
  const AFacts: TArray<TExportedSymbol>);
begin
  FUnitExports[AUnitName.ToLower].SetExportFacts(AFacts);
end;

procedure TProjectContext.RegisterImplicitEffects(const AUnitName: string;
  const AEffects: TArray<TImplicitEffect>; AKnown: Boolean);
begin
  FUnitExports[AUnitName.ToLower].SetImplicitEffects(AEffects, AKnown);
end;

function TProjectContext.LoadEffectFacts(const AUnitName: string): TUnitEffectFacts;
var LExports: TUnitExports;
begin
  Result := Default(TUnitEffectFacts);
  if not HasUnit(AUnitName) then
    Exit;
  LExports := FUnitExports[AUnitName.ToLower];
  Result.DirectEffects := LExports.HasInitialization;
  Result.UnknownEffects := LExports.UnknownEffects;
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

function TProjectContext.AssessHelpers(const AUnitName: string;
  const AVisibleUnits: TArray<string>; const AReferences: TArray<TMemberReference>;
  AKnown, AInterface: Boolean): THelperUse;
begin
  Result := THelperBinding.Assess(AUnitName, FUnitExports, AVisibleUnits,
    AReferences, AKnown, AInterface);
end;

function TProjectContext.UnitExportsIdentifier(const AUnitName, AIdentifier: string;
  const AAllUsedIdents: TArray<string>; AIncludeHelpers, AStructured: Boolean): Boolean;
var
  LExports: TUnitExports;
  LBaseIdent, LQualifiedUnit, LQualifiedBaseIdentifier: string;
begin
  Result := False;
  if not FUnitExports.TryGetValue(LowerCase(AUnitName), LExports) then
    Exit;
  LBaseIdent := AIdentifier;
  if TryResolveQualifiedUnit(AIdentifier, LQualifiedUnit, LQualifiedBaseIdentifier) then
  begin
    if not SameText(LQualifiedUnit, AUnitName) then
      Exit;
    LBaseIdent := TTypeName.FirstSegment(LQualifiedBaseIdentifier);
  end;
  Result := LExports.MatchesIdentifier(TTypeName.LastSegment(LBaseIdent), AStructured);
  if not Result and AStructured then
    Result := LExports.MatchesIdentifier(TTypeName.FirstSegment(LBaseIdent), True);
  if not Result and AIncludeHelpers then
    Result := LExports.MatchesLegacyHelper(TTypeName.Read(
      TTypeName.LastSegment(LBaseIdent)).Name, AAllUsedIdents);
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
      if not UnitExportsIdentifier(LUnitName, AIdentifier, [], False, True) then
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

procedure TAnalyzeUnitUses.InitializeFacts(const ATree: IUnitSyntaxTree);
var LMembers: IUnitMemberReferences; LSymbols: IUnitSymbolFacts;
  LBinding: TLocalSymbolBinding;
begin
  FReferences := nil;
  FUnknownReferences[False] := nil;
  FUnknownReferences[True] := nil;
  FReferencesKnown := Supports(ATree, IUnitMemberReferences, LMembers);
  if FReferencesKnown then
    FReferences := LMembers.GetMemberReferences;
  if not Supports(ATree, IUnitSymbolFacts, LSymbols) then
    Exit;
  LBinding := TLocalSymbolBinding.Create(LSymbols.GetSymbolFacts);
  try
    FUnknownReferences[False] := LBinding.Identifiers(False, True);
    FUnknownReferences[True] := LBinding.Identifiers(True, True);
  finally
    LBinding.Free;
  end;
end;

function TAnalyzeUnitUses.IsUnitUsed(AContext: TProjectContext;
  const AUnitName: string; const AUsedIdentifiers,
  AVisibleIdentifiers: TArray<string>): Boolean;
var
  LIdent: string;
begin
  Result := False;
  if FHelperUse = huUsed then
    Exit(True);
  for LIdent in AUsedIdentifiers do
  begin
    if AContext.UnitExportsIdentifier(AUnitName, LIdent,
      AVisibleIdentifiers, False, True) then
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
  LReason, LReference: string;
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
  for LReference in FUnknownReferences[FReferenceInterface] do
    if AContext.UnitExportsIdentifier(AUnitName, LReference, [], False, True) then
    begin
      ADecisions.Add(TDependencyDecision.Create(AUnitName, ASection, dsUnknown,
        daPreserve, 'Unresolved lexical binding for ' + LReference + '.'));
      Exit;
    end;
  FHelperUse := AContext.AssessHelpers(AUnitName, AVisibleUnits, FReferences,
    FReferencesKnown, FReferenceInterface);
  if FHelperUse = huUnknown then
  begin
    ADecisions.Add(TDependencyDecision.Create(AUnitName, ASection, dsUnknown,
      daPreserve, 'Helper receiver or precedence could not be resolved.'));
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
  LTree: IUnitSyntaxTree;
begin
  LTree := ASyntaxTree;
  Result := Default(TUnitAnalysisResult);
  Result.UnitName := ASyntaxTree.GetUnitName;
  InitializeFacts(LTree);
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
      FReferenceInterface := True;
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

      FReferenceInterface := False;
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
      FReferenceInterface := False;
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

