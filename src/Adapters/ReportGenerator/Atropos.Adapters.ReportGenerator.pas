unit Atropos.Adapters.ReportGenerator;

interface
uses
  Atropos.Core.Ports, System.Generics.Collections;

type
  TReportGeneratorAdapter = class(TInterfacedObject, IReportGenerator)
  private
    FReportLines: TList<string>;
    FMetricsLines: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddUnitProcessed(const AUnitName: string; const ARemovedUses, AMovedUses: TArray<string>);
    procedure AddMetrics(const ABefore, AAfter: TBuildMetrics);
    function GetReportContent: string;
  end;

implementation
uses
  System.SysUtils;

constructor TReportGeneratorAdapter.Create;
begin
  FReportLines := TList<string>.Create;
  FMetricsLines := TList<string>.Create;
end;

destructor TReportGeneratorAdapter.Destroy;
begin
  FMetricsLines.Free;
  FReportLines.Free;
  inherited;
end;

procedure TReportGeneratorAdapter.AddUnitProcessed(const AUnitName: string; const ARemovedUses, AMovedUses: TArray<string>);
var
  LUses: string;
begin
  if (Length(ARemovedUses) = 0) and (Length(AMovedUses) = 0) then
    Exit;

  FReportLines.Add('');
  FReportLines.Add('File: ' + AUnitName);
  
  if Length(ARemovedUses) > 0 then
  begin
    FReportLines.Add('  Removed Uses:');
    for LUses in ARemovedUses do
      FReportLines.Add('    - ' + LUses);
  end;
  
  if Length(AMovedUses) > 0 then
  begin
    FReportLines.Add('  Moved to Implementation Uses:');
    for LUses in AMovedUses do
      FReportLines.Add('    - ' + LUses);
  end;
end;

procedure TReportGeneratorAdapter.AddMetrics(const ABefore, AAfter: TBuildMetrics);
begin
  FMetricsLines.Add('');
  FMetricsLines.Add('Atropos - Metrics Report');
  FMetricsLines.Add('===============================');
  FMetricsLines.Add('Delphi Version: ' + ABefore.DelphiVersion);
  FMetricsLines.Add('');
  FMetricsLines.Add(Format('Units Removed: %d', [AAfter.RemovedUnitsCount]));
  FMetricsLines.Add(Format('Units Moved to Implementation: %d', [AAfter.MovedUnitsCount]));
  FMetricsLines.Add('');
  FMetricsLines.Add('Compile Time (Before): ' + IntToStr(ABefore.CompileTimeMs) + ' ms');
  FMetricsLines.Add('Compile Time (After): ' + IntToStr(AAfter.CompileTimeMs) + ' ms');
  FMetricsLines.Add(Format('Delta Time: %d ms', [AAfter.CompileTimeMs - ABefore.CompileTimeMs]));
  FMetricsLines.Add('');
  FMetricsLines.Add(Format('Hints (Before/After): %d / %d', [ABefore.Hints, AAfter.Hints]));
  FMetricsLines.Add(Format('Warnings (Before/After): %d / %d', [ABefore.Warnings, AAfter.Warnings]));
  FMetricsLines.Add('');
  
  if (ABefore.ExeSizeBytes > 0) and (AAfter.ExeSizeBytes > 0) then
  begin
    FMetricsLines.Add(Format('Exe Size (Before/After): %d KB / %d KB', [ABefore.ExeSizeBytes div 1024, AAfter.ExeSizeBytes div 1024]));
    FMetricsLines.Add(Format('Size Delta: %d KB', [(AAfter.ExeSizeBytes - ABefore.ExeSizeBytes) div 1024]));
  end
  else
    FMetricsLines.Add('Exe Size: Could not determine (usually MSBuild /t:Build does not emit EXE path).');
end;

function TReportGeneratorAdapter.GetReportContent: string;
var
  LResult: TStringBuilder;
  LLine: string;
begin
  if (FReportLines.Count = 0) and (FMetricsLines.Count = 0) then
    Exit('No files were processed.');

  LResult := TStringBuilder.Create;
  try
    for LLine in FMetricsLines do
      LResult.AppendLine(LLine);
      
    if (FMetricsLines.Count > 0) and (FReportLines.Count > 0) then 
      LResult.AppendLine('');

    if FReportLines.Count > 0 then
    begin
      LResult.AppendLine('Atropos - Processing Report');
      LResult.AppendLine('===============================');
      for LLine in FReportLines do
        LResult.AppendLine(LLine);
    end;

    Result := LResult.ToString;
  finally
    LResult.Free;
  end;
end;

end.
