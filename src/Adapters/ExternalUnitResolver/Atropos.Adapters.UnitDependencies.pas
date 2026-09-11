unit Atropos.Adapters.UnitDependencies;

interface

uses Atropos.Core.Ports, System.Generics.Collections;

type
  TUnitDependencyCache = class
  private
    FImports: TDictionary<string, TArray<string>>;
    FEffects: TDictionary<string, TArray<TImplicitEffect>>;
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
  end;

implementation

uses System.SysUtils;

constructor TUnitDependencyCache.Create;
begin
  inherited;
  FImports := TDictionary<string, TArray<string>>.Create;
  FEffects := TDictionary<string, TArray<TImplicitEffect>>.Create;
end;

destructor TUnitDependencyCache.Destroy;
begin
  FImports.Free;
  FEffects.Free;
  inherited;
end;

procedure TUnitDependencyCache.Clear;
begin
  FImports.Clear;
  FEffects.Clear;
end;

procedure TUnitDependencyCache.RegisterImports(const AName: string; const AImports: TArray<string>);
begin
  FImports.AddOrSetValue(AName.ToLowerInvariant, Copy(AImports));
end;

procedure TUnitDependencyCache.Capture(const AName: string; const ATree: IUnitSyntaxTree);
var LDiagnostics: IUnitAnalysisDiagnostics; LEffects: IUnitImplicitEffects;
begin
  FImports.Remove(AName.ToLowerInvariant);
  FEffects.Remove(AName.ToLowerInvariant);
  if Supports(ATree, IUnitImplicitEffects, LEffects) then
    RegisterEffects(AName, LEffects.GetImplicitEffects);
  if Supports(ATree, IUnitAnalysisDiagnostics, LDiagnostics) then
    if Length(LDiagnostics.GetIncompleteAnalysisReasons) > 0 then
      Exit;
  RegisterImports(AName, ATree.GetInterfaceUses + ATree.GetImplementationUses);
end;

procedure TUnitDependencyCache.CopyName(const ASource, ATarget: string);
var LImports: TArray<string>; LEffects: TArray<TImplicitEffect>;
begin
  if TryGet(ASource, LImports) then
    RegisterImports(ATarget, LImports);
  if TryGetEffects(ASource, LEffects) then
    RegisterEffects(ATarget, LEffects);
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
