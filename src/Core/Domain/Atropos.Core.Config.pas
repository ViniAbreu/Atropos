unit Atropos.Core.Config;

interface





type
  TToolConfig = record
  private
    FFormatOneUnitPerLine: Boolean;
    FSortUsesAlphabetically: Boolean;
    FMoveToImplementation: Boolean;
    FRemoveUnused: Boolean;
    FEnableDebug: Boolean;
    FExportHTML: Boolean;
    FExportTXT: Boolean;
  public
    property FormatOneUnitPerLine: Boolean read FFormatOneUnitPerLine write FFormatOneUnitPerLine;
    property SortUsesAlphabetically: Boolean read FSortUsesAlphabetically write FSortUsesAlphabetically;
    property MoveToImplementation: Boolean read FMoveToImplementation write FMoveToImplementation;
    property RemoveUnused: Boolean read FRemoveUnused write FRemoveUnused;
    property EnableDebug: Boolean read FEnableDebug write FEnableDebug;
    property ExportHTML: Boolean read FExportHTML write FExportHTML;
    property ExportTXT: Boolean read FExportTXT write FExportTXT;

    class function Default: TToolConfig; static;
  end;

implementation

class function TToolConfig.Default: TToolConfig;
begin
  Result.FFormatOneUnitPerLine := False;
  Result.FSortUsesAlphabetically := False;
  Result.FMoveToImplementation := False;
  Result.FRemoveUnused := False;
  Result.FEnableDebug := False;
  Result.FExportHTML := False;
  Result.FExportTXT := False;
end;

end.
