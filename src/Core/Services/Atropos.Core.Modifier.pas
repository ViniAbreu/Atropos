unit Atropos.Core.Modifier;

interface

uses Atropos.Core.Ports, Atropos.Core.Domain, Atropos.Core.Config,
  Atropos.Core.UsesEditPlan;

type
  TApplyUsesChanges = class
  private
    FFileService: IFileService;
    FConfig: TToolConfig;
  public
    constructor Create(AFileService: IFileService; AConfig: TToolConfig);
    function Prepare(const AFilePath: string; const AAnalysisResult: TUnitAnalysisResult): TUsesEditPlan;
    procedure ApplyPlan(const AFilePath: string; const APlan: TUsesEditPlan);
    procedure Execute(const AFilePath: string; const AAnalysisResult: TUnitAnalysisResult);
    class function RemoveUnitFromUsesClause(const ASource, AUnitToRemove: string; AIsInterface: Boolean): string;
    class function AddUnitToInterfaceUses(const ASource, AUnitToAdd: string): string;
    class function EnsureInterfaceImport(const ASource, AUnitToAdd: string): string;
  end;

implementation

uses Atropos.Core.Profiling, System.SysUtils, System.Classes, Atropos.Core.Analysis, Atropos.Core.UsesEditor,
  Atropos.Core.UsesSyntax;

class function TApplyUsesChanges.EnsureInterfaceImport(const ASource, AUnitToAdd: string): string;
var LEditor: TUsesEditor; LDocument: TUsesSource; LClause: TUsesClause; LIndex: Integer;
begin
  LEditor := TUsesEditor.Create(ASource);
  LDocument := TUsesSource.Create(ASource);
  try
    if LDocument.Find(AUnitToAdd, usImplementation, LClause, LIndex) then
      LEditor.Move(AUnitToAdd, usImplementation);
    if not Assigned(LClause) then
      LEditor.Add(AUnitToAdd, AUnitToAdd, usInterface);
    Result := LEditor.Source;
  finally
    LDocument.Free;
    LEditor.Free;
  end;
end;

constructor TApplyUsesChanges.Create(AFileService: IFileService; AConfig: TToolConfig);
begin
  FFileService := AFileService;
  FConfig := AConfig;
end;

function TApplyUsesChanges.Prepare(const AFilePath: string;
  const AAnalysisResult: TUnitAnalysisResult): TUsesEditPlan;
var LProfileScope: IInterface; LPlanner: TUsesEditPlanner; LPreviewConfig: TToolConfig;
begin
  LProfileScope := TExecutionProfile.Measure('editing-plan', AFilePath);
  LPreviewConfig := FConfig;
  if FConfig.DryRun and not FConfig.RemoveUnused and not FConfig.MoveToImplementation then
    LPreviewConfig := FConfig.WithRemoveUnused(True).WithMoveToImplementation(True);
  LPlanner := TUsesEditPlanner.Create(FFileService.ReadFileContent(AFilePath), AFilePath, LPreviewConfig);
  try
    Result := LPlanner.Prepare(AAnalysisResult);
  finally
    LPlanner.Free;
  end;
end;

procedure TApplyUsesChanges.ApplyPlan(const AFilePath: string; const APlan: TUsesEditPlan);
var LProfileScope: IInterface; LCurrent: string;
begin
  LProfileScope := TExecutionProfile.Measure('editing-write', AFilePath);
  if FConfig.DryRun or not APlan.HasChanges then
    Exit;
  LCurrent := FFileService.ReadFileContent(AFilePath);
  if LCurrent = APlan.Updated then
    Exit;
  if LCurrent <> APlan.Original then
    raise EInvalidOperation.Create('Source changed after the edit plan was prepared: ' + AFilePath);
  FFileService.BackupFile(AFilePath);
  FFileService.WriteFileContent(AFilePath, APlan.Updated);
end;

procedure TApplyUsesChanges.Execute(const AFilePath: string; const AAnalysisResult: TUnitAnalysisResult);
begin
  ApplyPlan(AFilePath, Prepare(AFilePath, AAnalysisResult));
end;

class function TApplyUsesChanges.RemoveUnitFromUsesClause(const ASource,
  AUnitToRemove: string; AIsInterface: Boolean): string;
var LEditor: TUsesEditor; LSection: TUsesSection;
begin
  LSection := usImplementation;
  if AIsInterface then
    LSection := usInterface;
  LEditor := TUsesEditor.Create(ASource);
  try
    LEditor.Remove(AUnitToRemove, LSection);
    Result := LEditor.Source;
  finally
    LEditor.Free;
  end;
end;

class function TApplyUsesChanges.AddUnitToInterfaceUses(const ASource, AUnitToAdd: string): string;
var LEditor: TUsesEditor;
begin
  LEditor := TUsesEditor.Create(ASource);
  try
    LEditor.Add(AUnitToAdd, AUnitToAdd, usInterface);
    Result := LEditor.Source;
  finally
    LEditor.Free;
  end;
end;

end.
