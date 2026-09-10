unit Atropos.Adapters.UnitDependencies;

interface

uses Atropos.Core.Ports, System.Generics.Collections;

type
  TUnitDependencyCache = class
  private
    FImports: TDictionary<string, TArray<string>>;
    FEffects: TDictionary<string, TArray<TImplicitEffect>>;
    FExports: TDictionary<string, TArray<TExportedSymbol>>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure RegisterImports(const AName: string; const AImports: TArray<string>);
    procedure Capture(const AName: string; const ATree: IUnitSyntaxTree);
    procedure CopyName(const ASource, ATarget: string);
    function TryGet(const AName: string; out AImports: TArray<string>): Boolean;
    procedure RegisterEffects(const AName: string; const AEffects: TArray<TImplicitEffect>);
    function TryGetEffects(const AName: string; out AEffects: TArray<TImplicitEffect>): Boolean;
    procedure RegisterExports(const AName: string; const AFacts: TArray<TExportedSymbol>);
    function TryGetExports(const AName: string; out AFacts: TArray<TExportedSymbol>): Boolean;
  end;

implementation

uses System.SysUtils;

constructor TUnitDependencyCache.Create;
begin
  inherited;
  FImports := TDictionary<string, TArray<string>>.Create;
  FEffects := TDictionary<string, TArray<TImplicitEffect>>.Create;
  FExports := TDictionary<string, TArray<TExportedSymbol>>.Create;
end;

destructor TUnitDependencyCache.Destroy;
begin
  FImports.Free;
  FEffects.Free;
  FExports.Free;
  inherited;
end;

procedure TUnitDependencyCache.Clear;
begin
  FImports.Clear;
  FEffects.Clear;
  FExports.Clear;
end;

procedure TUnitDependencyCache.RegisterImports(const AName: string; const AImports: TArray<string>);
begin
  FImports.AddOrSetValue(AName.ToLowerInvariant, Copy(AImports));
end;

procedure TUnitDependencyCache.Capture(const AName: string; const ATree: IUnitSyntaxTree);
var LDiagnostics: IUnitAnalysisDiagnostics; LEffects: IUnitImplicitEffects;
  LExports: IUnitExportFacts;
begin
  FImports.Remove(AName.ToLowerInvariant);
  FEffects.Remove(AName.ToLowerInvariant);
  FExports.Remove(AName.ToLowerInvariant);
  if Supports(ATree, IUnitImplicitEffects, LEffects) then
    RegisterEffects(AName, LEffects.GetImplicitEffects);
  if Supports(ATree, IUnitAnalysisDiagnostics, LDiagnostics) then
    if Length(LDiagnostics.GetIncompleteAnalysisReasons) > 0 then
      Exit;
  RegisterImports(AName, ATree.GetInterfaceUses + ATree.GetImplementationUses);
  if Supports(ATree, IUnitExportFacts, LExports) then
    RegisterExports(AName, LExports.GetExportFacts);
end;

procedure TUnitDependencyCache.CopyName(const ASource, ATarget: string);
var LImports: TArray<string>; LEffects: TArray<TImplicitEffect>; LFacts: TArray<TExportedSymbol>;
begin
  if TryGet(ASource, LImports) then
    RegisterImports(ATarget, LImports);
  if TryGetEffects(ASource, LEffects) then
    RegisterEffects(ATarget, LEffects);
  if TryGetExports(ASource, LFacts) then
    RegisterExports(ATarget, LFacts);
end;

procedure TUnitDependencyCache.RegisterExports(const AName: string; const AFacts: TArray<TExportedSymbol>);
begin
  FExports.AddOrSetValue(AName.ToLowerInvariant, Copy(AFacts));
end;

function TUnitDependencyCache.TryGetExports(const AName: string; out AFacts: TArray<TExportedSymbol>): Boolean;
begin
  Result := FExports.TryGetValue(AName.ToLowerInvariant, AFacts);
  AFacts := Copy(AFacts);
end;

function TUnitDependencyCache.TryGet(const AName: string; out AImports: TArray<string>): Boolean;
begin
  Result := FImports.TryGetValue(AName.ToLowerInvariant, AImports);
  AImports := Copy(AImports);
end;

procedure TUnitDependencyCache.RegisterEffects(const AName: string;
  const AEffects: TArray<TImplicitEffect>);
begin
  FEffects.AddOrSetValue(AName.ToLowerInvariant, Copy(AEffects));
end;

function TUnitDependencyCache.TryGetEffects(const AName: string;
  out AEffects: TArray<TImplicitEffect>): Boolean;
begin
  Result := FEffects.TryGetValue(AName.ToLowerInvariant, AEffects);
  AEffects := Copy(AEffects);
end;

end.
