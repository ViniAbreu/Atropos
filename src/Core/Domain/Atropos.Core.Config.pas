unit Atropos.Core.Config;

interface

type
  TToolConfig = record
  private
    FMoveToImplementation: Boolean;
    FRemoveUnused: Boolean;
    FEnableDebug: Boolean;
    FExportHTML: Boolean;
    FExportTXT: Boolean;
  public
    property MoveToImplementation: Boolean read FMoveToImplementation write FMoveToImplementation;
    property RemoveUnused: Boolean read FRemoveUnused write FRemoveUnused;
    property EnableDebug: Boolean read FEnableDebug write FEnableDebug;
    property ExportHTML: Boolean read FExportHTML write FExportHTML;
    property ExportTXT: Boolean read FExportTXT write FExportTXT;

    class function Default: TToolConfig; static;
    function WithMoveToImplementation(const AValue: Boolean): TToolConfig;
    function WithRemoveUnused(const AValue: Boolean): TToolConfig;
    function WithEnableDebug(const AValue: Boolean): TToolConfig;
  end;

implementation

class function TToolConfig.Default: TToolConfig;
begin
  Result.FMoveToImplementation := False;
  Result.FRemoveUnused := False;
  Result.FEnableDebug := False;
  Result.FExportHTML := False;
  Result.FExportTXT := False;
end;

function TToolConfig.WithMoveToImplementation(const AValue: Boolean): TToolConfig;
begin
  Result := Self;
  Result.FMoveToImplementation := AValue;
end;

function TToolConfig.WithRemoveUnused(const AValue: Boolean): TToolConfig;
begin
  Result := Self;
  Result.FRemoveUnused := AValue;
end;

function TToolConfig.WithEnableDebug(const AValue: Boolean): TToolConfig;
begin
  Result := Self;
  Result.FEnableDebug := AValue;
end;

end.
