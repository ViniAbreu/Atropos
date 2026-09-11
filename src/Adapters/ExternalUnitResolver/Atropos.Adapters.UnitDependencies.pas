unit Atropos.Adapters.UnitDependencies;

interface

uses Atropos.Core.Ports, System.Generics.Collections;

type
  TUnitDependencyCache = class
  private
    FImports: TDictionary<string, TArray<string>>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure RegisterImports(const AName: string; const AImports: TArray<string>);
    procedure Capture(const AName: string; const ATree: IUnitSyntaxTree);
    procedure CopyName(const ASource, ATarget: string);
    function TryGet(const AName: string; out AImports: TArray<string>): Boolean;
  end;

implementation

uses System.SysUtils;

constructor TUnitDependencyCache.Create;
begin
  inherited;
  FImports := TDictionary<string, TArray<string>>.Create;
end;

destructor TUnitDependencyCache.Destroy;
begin
  FImports.Free;
  inherited;
end;

procedure TUnitDependencyCache.Clear;
begin
  FImports.Clear;
end;

procedure TUnitDependencyCache.RegisterImports(const AName: string; const AImports: TArray<string>);
begin
  FImports.AddOrSetValue(AName.ToLowerInvariant, Copy(AImports));
end;

procedure TUnitDependencyCache.Capture(const AName: string; const ATree: IUnitSyntaxTree);
var LDiagnostics: IUnitAnalysisDiagnostics;
begin
  FImports.Remove(AName.ToLowerInvariant);
  if Supports(ATree, IUnitAnalysisDiagnostics, LDiagnostics) then
    if Length(LDiagnostics.GetIncompleteAnalysisReasons) > 0 then
      Exit;
  RegisterImports(AName, ATree.GetInterfaceUses + ATree.GetImplementationUses);
end;

procedure TUnitDependencyCache.CopyName(const ASource, ATarget: string);
var LImports: TArray<string>;
begin
  if TryGet(ASource, LImports) then
    RegisterImports(ATarget, LImports);
end;

function TUnitDependencyCache.TryGet(const AName: string; out AImports: TArray<string>): Boolean;
begin
  Result := FImports.TryGetValue(AName.ToLowerInvariant, AImports);
  AImports := Copy(AImports);
end;

end.
