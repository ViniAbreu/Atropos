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
  Atropos.Adapters.TargetResolver, Atropos.Adapters.ProjectSourceMappings;

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
  LParser: TDelphiASTAdapter;
  LContext: TProjectCompilationContext;
begin
  LReader := TCompilerSymbolReader.Create(FRunner, FCancel);
  try
    LSymbols := LReader.Read(AContext, ADelphiPath);
  finally
    LReader.Free;
  end;
  LParser := TDelphiASTAdapter.Create(AContext, LSymbols);
  Result.Parser := LParser;
  LParser.BeginAnalysis;
  LParser.RegisterProjectInputs(AContext.ProjectFiles);
  LContext := TProjectSourceMappings.Resolve(AContext, Result.Parser);
  Result.UnitPaths := LContext.UnitPaths;
  Result.Resolver := TTargetUnitResolver.Create(Result.Parser, LContext, ADelphiPath);
end;

end.
