unit Atropos.Adapters.TargetAnalysisFactory;

interface

uses Atropos.Core.Ports, Atropos.Core.Compilation, Atropos.Adapters.BuildService;

type
  TTargetAnalysisFactory = class(TInterfacedObject, ITargetAnalysisFactory)
  private
    FRunner: IBuildProcessRunner;
    FCancel: TCancellationCheck;
  public
    constructor Create(const ARunner: IBuildProcessRunner;
      const ACancel: TCancellationCheck);
    function CreateForTarget(const AContext: TProjectCompilationContext;
      const ADelphiPath: string): TTargetAnalysisServices;
  end;

implementation

uses Atropos.Adapters.CompilerSymbols, Atropos.Adapters.DelphiAST,
  Atropos.Adapters.TargetResolver;

constructor TTargetAnalysisFactory.Create(const ARunner: IBuildProcessRunner;
  const ACancel: TCancellationCheck);
begin
  inherited Create;
  FRunner := ARunner;
  FCancel := ACancel;
end;

function TTargetAnalysisFactory.CreateForTarget(
  const AContext: TProjectCompilationContext;
  const ADelphiPath: string): TTargetAnalysisServices;
var
  LReader: TCompilerSymbolReader;
  LSymbols: TCompilerSymbols;
begin
  LReader := TCompilerSymbolReader.Create(FRunner, FCancel);
  try
    LSymbols := LReader.Read(AContext, ADelphiPath);
  finally
    LReader.Free;
  end;
  Result.Parser := TDelphiASTAdapter.Create(AContext, LSymbols);
  Result.Resolver := TTargetUnitResolver.Create(Result.Parser, AContext, ADelphiPath);
end;

end.
