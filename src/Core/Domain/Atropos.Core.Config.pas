unit Atropos.Core.Config;

interface

uses
  Atropos.Core.Ports;

type
  TToolConfig = record
  private
    FMoveToImplementation: Boolean;
    FRemoveUnused: Boolean;
    FEnableDebug: Boolean;
    FExportHTML: Boolean;
    FExportTXT: Boolean;
    FOutputDirectory: string;
    FDryRun: Boolean;
    FBuildTargets: TArray<TBuildTarget>;
  public
    property MoveToImplementation: Boolean read FMoveToImplementation write FMoveToImplementation;
    property RemoveUnused: Boolean read FRemoveUnused write FRemoveUnused;
    property EnableDebug: Boolean read FEnableDebug write FEnableDebug;
    property ExportHTML: Boolean read FExportHTML write FExportHTML;
    property ExportTXT: Boolean read FExportTXT write FExportTXT;
    property OutputDirectory: string read FOutputDirectory write FOutputDirectory;
    property DryRun: Boolean read FDryRun write FDryRun;
    property BuildTargets: TArray<TBuildTarget> read FBuildTargets;

    class function Default: TToolConfig; static;
    function WithMoveToImplementation(const AValue: Boolean): TToolConfig;
    function WithRemoveUnused(const AValue: Boolean): TToolConfig;
    function WithEnableDebug(const AValue: Boolean): TToolConfig;
    function WithOutputDirectory(const AValue: string): TToolConfig;
    procedure AddBuildTarget(const ATarget: TBuildTarget);
  end;

implementation

class function TToolConfig.Default: TToolConfig;
begin
  Result.FMoveToImplementation := False;
  Result.FRemoveUnused := False;
  Result.FEnableDebug := False;
  Result.FExportHTML := False;
  Result.FExportTXT := False;
  Result.FOutputDirectory := '';
  Result.FDryRun := False;
  Result.FBuildTargets := [];
end;

procedure TToolConfig.AddBuildTarget(const ATarget: TBuildTarget);
begin
  SetLength(FBuildTargets, Length(FBuildTargets) + 1);
  FBuildTargets[High(FBuildTargets)] := ATarget;
end;

function TToolConfig.WithOutputDirectory(const AValue: string): TToolConfig;
begin
  Result := Self;
  Result.FOutputDirectory := AValue;
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
