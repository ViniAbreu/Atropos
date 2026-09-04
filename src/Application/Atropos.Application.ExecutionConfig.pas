unit Atropos.Application.ExecutionConfig;

interface

uses
  Atropos.Core.Config;

type
  TExecutionConfigFactory = class
  public
    class function FromSelections(ARemoveUnused, AMoveToImplementation,
      AEnableDebug: Boolean): TToolConfig; static;
  end;

implementation

class function TExecutionConfigFactory.FromSelections(ARemoveUnused,
  AMoveToImplementation, AEnableDebug: Boolean): TToolConfig;
begin
  Result := TToolConfig.Default;
  Result.RemoveUnused := ARemoveUnused;
  Result.MoveToImplementation := AMoveToImplementation;
  Result.EnableDebug := AEnableDebug;
end;

end.
