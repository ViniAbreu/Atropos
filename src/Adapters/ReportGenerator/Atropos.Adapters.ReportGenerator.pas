unit Atropos.Adapters.ReportGenerator;

interface
uses
  Atropos.Core.Ports,
  System.Generics.Collections;

type
  TReportGeneratorAdapter = class(TInterfacedObject, IReportGenerator)
  private
    FReportLines: TList<string>;
    FMetricsBefore: TBuildMetrics;
    FMetricsAfter: TBuildMetrics;
    FHasMetrics: Boolean;
    FProjectName: string;
    FAnalysisTimeMs: Int64;
    FUnitsAnalyzed: Integer;
    FSearchPaths: Integer;
    function FormatDeltaPct(ADiff: Double; AIsTimeMetric: Boolean): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddUnitProcessed(const AUnitName: string; const ARemovedUses, AMovedUses: TArray<string>);
    procedure AddMetrics(const ABefore, AAfter: TBuildMetrics);
    procedure SetAnalysisInfo(const AProjectName: string; AAnalysisTimeMs: Int64; AUnitsAnalyzed, ASearchPaths: Integer);
    function GetReportContentTXT: string;
    function GetReportContentHTML: string;
  end;

implementation
uses System.Math, System.StrUtils,
  System.SysUtils;

const
  HTML_BASE_TEMPLATE = 
    '<!DOCTYPE html>' + sLineBreak +
    '<html lang="en">' + sLineBreak +
    '<head>' + sLineBreak +
    '  <meta charset="UTF-8">' + sLineBreak +
    '  <meta name="viewport" content="width=device-width, initial-scale=1.0">' + sLineBreak +
    '  <title>Atropos - Report</title>' + sLineBreak +
    '  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">' + sLineBreak +
    '  <style>' + sLineBreak +
    '    :root { --bg-body: #18181b; --bg-nav: #27272a; --bg-card: #27272a; --border: #3f3f46; --text-main: #f4f4f5; --text-muted: #a1a1aa; --accent-blue: #38bdf8; --status-passed: #22c55e; --status-failed: #ef4444; --issue-removed: #ef4444; --issue-moved: #f59e0b; }' + sLineBreak +
    '    body { font-family: "Inter", sans-serif; background-color: var(--bg-body); color: var(--text-main); margin: 0; padding: 0; line-height: 1.5; height: 100vh; display: flex; flex-direction: column; overflow: hidden; }' + sLineBreak +
    '    * { box-sizing: border-box; }' + sLineBreak +
    '    .navbar { background-color: var(--bg-nav); border-bottom: 1px solid var(--border); padding: 12px 24px; display: flex; align-items: center; gap: 25px; flex-shrink: 0; }' + sLineBreak +
    '    .navbar-logo { font-weight: 700; font-size: 1.2rem; color: var(--accent-blue); letter-spacing: -0.5px; }' + sLineBreak +
    '    .navbar-item { color: var(--text-main); font-size: 0.9rem; font-weight: 500; text-transform: uppercase; letter-spacing: 1px; cursor: pointer; border-bottom: 2px solid var(--accent-blue); padding-bottom: 4px; }' + sLineBreak +
    '    .container { width: 100%; max-width: 1200px; margin: 0 auto; padding: 30px 24px; display: flex; flex-direction: column; flex: 1; overflow: hidden; }' + sLineBreak +
    '    .header-title { font-size: 1.8rem; font-weight: 600; margin: 0 0 5px 0; flex-shrink: 0; }' + sLineBreak +
    '    .header-subtitle { color: var(--text-muted); font-size: 0.9rem; margin-bottom: 30px; flex-shrink: 0; }' + sLineBreak +
    '    .dashboard-top { display: flex; gap: 20px; margin-bottom: 30px; flex-shrink: 0; }' + sLineBreak +
    '    .info-card { background-color: var(--bg-card); border: 1px solid var(--border); border-radius: 4px; padding: 20px; flex: 1.5; display: flex; flex-direction: column; justify-content: center; border-left: 4px solid var(--accent-blue); }' + sLineBreak +
    '    .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; }' + sLineBreak +
    '    .info-item { display: flex; flex-direction: column; }' + sLineBreak +
    '    .info-label { font-size: 0.75rem; text-transform: uppercase; color: var(--text-muted); font-weight: 600; margin-bottom: 4px; white-space: nowrap; }' + sLineBreak +
    '    .info-value { font-size: 1.1rem; font-weight: 600; color: var(--text-main); white-space: nowrap; }' + sLineBreak +
    '    .metrics-grid { display: flex; flex: 3; gap: 15px; }' + sLineBreak +
    '    .metric-card { background-color: var(--bg-card); border: 1px solid var(--border); border-radius: 4px; padding: 20px; flex: 1; display: flex; flex-direction: column; }' + sLineBreak +
    '    .metric-title { font-size: 0.85rem; color: var(--text-muted); font-weight: 500; margin-bottom: 15px; display: flex; align-items: center; gap: 8px; white-space: nowrap; }' + sLineBreak +
    '    .metric-value { font-size: 1.8rem; font-weight: 600; color: var(--text-main); white-space: nowrap; }' + sLineBreak +
    '    .metric-delta { font-size: 0.85rem; margin-top: 5px; white-space: nowrap; }' + sLineBreak +
    '    .delta-positive { color: var(--status-passed); }' + sLineBreak +
    '    .delta-negative { color: var(--status-failed); }' + sLineBreak +
    '    .issues-section { display: flex; flex-direction: column; flex: 1; overflow: hidden; }' + sLineBreak +
    '    .issues-section-title { font-size: 1.2rem; font-weight: 600; margin-bottom: 15px; padding-bottom: 10px; border-bottom: 1px solid var(--border); flex-shrink: 0; }' + sLineBreak +
    '    .issue-list { display: flex; flex-direction: column; gap: 10px; overflow-y: auto; padding-right: 10px; }' + sLineBreak +
    '    ::-webkit-scrollbar { width: 8px; }' + sLineBreak +
    '    ::-webkit-scrollbar-track { background: transparent; }' + sLineBreak +
    '    ::-webkit-scrollbar-thumb { background: #3f3f46; border-radius: 4px; }' + sLineBreak +
    '    ::-webkit-scrollbar-thumb:hover { background: #52525b; }' + sLineBreak +
    '    .issue-item { background-color: var(--bg-card); border: 1px solid var(--border); border-radius: 4px; transition: border-color 0.2s; }' + sLineBreak +
    '    .issue-item:hover { border-color: #52525b; }' + sLineBreak +
    '    .issue-summary { padding: 12px 16px; cursor: pointer; display: flex; align-items: center; gap: 15px; user-select: none; }' + sLineBreak +
    '    .issue-summary::-webkit-details-marker { display: none; }' + sLineBreak +
    '    .issue-icon { font-size: 1.2rem; color: var(--text-muted); transition: transform 0.2s; }' + sLineBreak +
    '    details[open] .issue-icon { transform: rotate(90deg); }' + sLineBreak +
    '    .issue-file { font-family: "Consolas", "JetBrains Mono", monospace; font-size: 0.95rem; font-weight: 500; flex: 1; }' + sLineBreak +
    '    .issue-badges { display: flex; gap: 8px; }' + sLineBreak +
    '    .badge { font-size: 0.75rem; padding: 2px 8px; border-radius: 12px; font-weight: 600; color: #fff; }' + sLineBreak +
    '    .badge-removed { background-color: var(--issue-removed); }' + sLineBreak +
    '    .badge-moved { background-color: var(--issue-moved); }' + sLineBreak +
    '    .issue-details { padding: 15px; border-top: 1px solid var(--border); background-color: rgba(0,0,0,0.15); animation: fadeIn 0.3s ease; }' + sLineBreak +
    '    @keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }' + sLineBreak +
    '    .uses-table { width: 100%; border-collapse: collapse; font-family: "Consolas", "JetBrains Mono", monospace; font-size: 0.85rem; }' + sLineBreak +
    '    .uses-table th { text-align: left; padding: 8px; color: var(--text-muted); border-bottom: 1px solid var(--border); font-weight: 500; }' + sLineBreak +
    '    .uses-table td { padding: 8px; border-bottom: 1px solid var(--border); }' + sLineBreak +
    '    .uses-table tr:last-child td { border-bottom: none; }' + sLineBreak +
    '    .type-icon { display: inline-block; width: 16px; height: 16px; border-radius: 50%; text-align: center; line-height: 16px; font-size: 10px; color: white; margin-right: 8px; }' + sLineBreak +
    '    .icon-rm { background-color: var(--issue-removed); }' + sLineBreak +
    '    .icon-mv { background-color: var(--issue-moved); }' + sLineBreak +
    '  </style>' + sLineBreak +
    '</head>' + sLineBreak +
    '<body>' + sLineBreak +
    '  <div class="navbar">' + sLineBreak +
    '    <div class="navbar-logo">ATROPOS</div>' + sLineBreak +
    '    <div class="navbar-item">Overview</div>' + sLineBreak +
    '  </div>' + sLineBreak +
    '  <div class="container">' + sLineBreak +
    '    <h1 class="header-title">Optimization Report</h1>' + sLineBreak +
    '    <div class="header-subtitle">Analysis finished successfully &bull; Project: {{PROJECT_NAME}}</div>' + sLineBreak +
    '    <div class="dashboard-top">' + sLineBreak +
    '      <div class="info-card">' + sLineBreak +
    '        <div class="info-grid">' + sLineBreak +
    '          <div class="info-item"><span class="info-label">Delphi Version</span><span class="info-value">{{DELPHI_VERSION}}</span></div>' + sLineBreak +
    '          <div class="info-item"><span class="info-label">Analysis Time</span><span class="info-value">{{ANALYSIS_TIME}}</span></div>' + sLineBreak +
    '          <div class="info-item"><span class="info-label">Units Analyzed</span><span class="info-value">{{UNITS_ANALYZED}}</span></div>' + sLineBreak +
    '          <div class="info-item"><span class="info-label">Search Paths</span><span class="info-value">{{SEARCH_PATHS}}</span></div>' + sLineBreak +
    '        </div>' + sLineBreak +
    '      </div>' + sLineBreak +
    '      <div class="metrics-grid">' + sLineBreak +
    '{{METRICS_HTML}}' + sLineBreak +
    '      </div>' + sLineBreak +
    '    </div>' + sLineBreak +
    '    <div class="issues-section">' + sLineBreak +
    '      <div class="issues-section-title">Unit Dependency Issues (Resolved)</div>' + sLineBreak +
    '      <div class="issue-list">' + sLineBreak +
    '{{ISSUES_HTML}}' + sLineBreak +
    '      </div>' + sLineBreak +
    '    </div>' + sLineBreak +
    '  </div>' + sLineBreak +
    '</body>' + sLineBreak +
    '</html>';

  HTML_METRICS_TEMPLATE =
    '        <div class="metric-card">' + sLineBreak +
    '          <div class="metric-title">Cleaned Units</div>' + sLineBreak +
    '          <div class="metric-value">{{CLEANED_COUNT}}</div>' + sLineBreak +
    '          <div class="metric-delta delta-positive">{{CLEANED_COUNT}} uses removed</div>' + sLineBreak +
    '        </div>' + sLineBreak +
    '        <div class="metric-card">' + sLineBreak +
    '          <div class="metric-title">Moved Units</div>' + sLineBreak +
    '          <div class="metric-value">{{MOVED_COUNT}}</div>' + sLineBreak +
    '          <div class="metric-delta delta-positive">{{MOVED_COUNT}} moved to implementation</div>' + sLineBreak +
    '        </div>' + sLineBreak +
    '        <div class="metric-card">' + sLineBreak +
    '          <div class="metric-title">Hints removed</div>' + sLineBreak +
    '          <div class="metric-value">{{HINTS_FIXED_COUNT}}</div>' + sLineBreak +
    '          <div class="metric-delta delta-positive">{{HINTS_FIXED_COUNT}} fixed</div>' + sLineBreak +
    '        </div>' + sLineBreak +
    '        <div class="metric-card">' + sLineBreak +
    '          <div class="metric-title">Compile Time</div>' + sLineBreak +
    '          <div class="metric-value">{{COMPILE_TIME}}</div>' + sLineBreak +
    '          <div class="metric-delta {{TIME_COLOR}}">{{TIME_DELTA}}{{TIME_PCT}}</div>' + sLineBreak +
    '        </div>' + sLineBreak +
    '        <div class="metric-card">' + sLineBreak +
    '          <div class="metric-title">Exe Size</div>' + sLineBreak +
    '          <div class="metric-value">{{EXE_SIZE}} <span style="font-size:1rem; color:var(--text-muted)">MB</span></div>' + sLineBreak +
    '          <div class="metric-delta {{SIZE_COLOR}}">{{SIZE_DELTA}} MB{{SIZE_PCT}}</div>' + sLineBreak +
    '        </div>';
    
  HTML_ISSUE_TEMPLATE_START =
    '        <details class="issue-item">' + sLineBreak +
    '          <summary class="issue-summary">' + sLineBreak +
    '            <div class="issue-icon">&#9654;</div>' + sLineBreak +
    '            <div class="issue-file">{{FILE_NAME}}</div>' + sLineBreak +
    '          </summary>' + sLineBreak +
    '          <div class="issue-details">' + sLineBreak +
    '            <table class="uses-table">' + sLineBreak +
    '              <thead><tr><th width="150">Action</th><th>Unit Name</th><th>Impact</th></tr></thead>' + sLineBreak +
    '              <tbody>';
    
  HTML_ISSUE_TEMPLATE_END =
    '              </tbody></table></div></details>';
    
  HTML_ISSUE_ITEM_TEMPLATE = 
    '                <tr>' + sLineBreak +
    '                  <td><span class="type-icon {{ICON_CLASS}}">{{ICON_CHAR}}</span> {{ACTION_NAME}}</td>' + sLineBreak +
    '                  <td>{{UNIT_NAME}}</td>' + sLineBreak +
    '                  <td style="color:var(--text-muted)">{{IMPACT_DESC}}</td>' + sLineBreak +
    '                </tr>';

constructor TReportGeneratorAdapter.Create;
begin
  FReportLines := TList<string>.Create;
end;

destructor TReportGeneratorAdapter.Destroy;
begin
  FReportLines.Free;
  inherited;
end;

procedure TReportGeneratorAdapter.AddUnitProcessed(const AUnitName: string; const ARemovedUses, AMovedUses: TArray<string>);
var
  LUses: string;
begin
  if (Length(ARemovedUses) = 0) and (Length(AMovedUses) = 0) then
    Exit;
    
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
  
  FReportLines.Add('');
end;

procedure TReportGeneratorAdapter.SetAnalysisInfo(const AProjectName: string; AAnalysisTimeMs: Int64; AUnitsAnalyzed, ASearchPaths: Integer);
begin
  FProjectName := AProjectName;
  FAnalysisTimeMs := AAnalysisTimeMs;
  FUnitsAnalyzed := AUnitsAnalyzed;
  FSearchPaths := ASearchPaths;
end;

procedure TReportGeneratorAdapter.AddMetrics(const ABefore, AAfter: TBuildMetrics);
begin
  FMetricsBefore := ABefore;
  FMetricsAfter := AAfter;
  FHasMetrics := True;
end;

function FormatTimeMs(AMs: Int64): string;
var
  LMin: Integer;
  LSec: Integer;
  LMillis: Integer;
begin
  LMin := AMs div 60000;
  LSec := (AMs mod 60000) div 1000;
  LMillis := AMs mod 1000;
  Result := Format('%.2d:%.2d.%.3d', [LMin, LSec, LMillis]);
end;

function TReportGeneratorAdapter.FormatDeltaPct(ADiff: Double; AIsTimeMetric: Boolean): string;
var
  LAbsDiff: Double;
begin
  LAbsDiff := Abs(ADiff);
  if LAbsDiff < 0.05 then
    Exit(EmptyStr);

  Result := Format(' (%.1f%% %s)', [LAbsDiff, IfThen(AIsTimeMetric, 'slower', 'larger')]);
  if ADiff < 0 then
    Result := Format(' (%.1f%% %s)', [LAbsDiff, IfThen(AIsTimeMetric, 'faster', 'smaller')]);
end;

function TReportGeneratorAdapter.GetReportContentTXT: string;
var
  LResult: TStringBuilder;
  LLine: string;
  LTimeDelta: Double;
  LSizeDelta: Double;
begin
  if (FReportLines.Count = 0) and not FHasMetrics then
    Exit('No files were processed.');

  LResult := TStringBuilder.Create;
  try
    LResult.AppendLine('Atropos - Optimization Report');
    LResult.AppendLine('========================================================');
    LResult.AppendLine('Project: ' + FProjectName);
    LResult.AppendLine('Analysis Time: ' + FormatTimeMs(FAnalysisTimeMs));
    LResult.AppendLine('Units Analyzed: ' + FUnitsAnalyzed.ToString);
    LResult.AppendLine('Search Paths: ' + FSearchPaths.ToString);
    LResult.AppendLine('');
    
    if FHasMetrics then
    begin
      LResult.AppendLine('Atropos - Metrics Report');
      LResult.AppendLine('========================================================');
      LResult.AppendLine('Delphi Version: ' + FMetricsBefore.DelphiVersion);
      LResult.AppendLine('');
      LResult.AppendLine('Cleaned Units (Removed Uses): ' + FMetricsAfter.RemovedUnitsCount.ToString);
      LResult.AppendLine('Moved Units (To Implementation): ' + FMetricsAfter.MovedUnitsCount.ToString);
      LResult.AppendLine('Hints removed: ' + FMetricsAfter.ResolvedInlineHintsCount.ToString);
      LResult.AppendLine('');
      LResult.AppendLine('Compile Time (Before): ' + FormatTimeMs(FMetricsBefore.CompileTimeMs));
      LResult.AppendLine('Compile Time (After): ' + FormatTimeMs(FMetricsAfter.CompileTimeMs));
      
      LTimeDelta := (FMetricsAfter.CompileTimeMs - FMetricsBefore.CompileTimeMs) / 1000.0;
      if LTimeDelta < 0 then
        LResult.AppendLine('Delta Time: ' + Format('%.2fs faster', [Abs(LTimeDelta)]));
      if LTimeDelta > 0 then
        LResult.AppendLine('Delta Time: ' + Format('%.2fs slower', [Abs(LTimeDelta)]));
      if SameValue(LTimeDelta, 0.0, 0.001) then
        LResult.AppendLine('Delta Time: 0s');
        
      LResult.AppendLine('');
      LResult.AppendLine(Format('Hints (Before/After): %d / %d', [FMetricsBefore.Hints, FMetricsAfter.Hints]));
      LResult.AppendLine(Format('Warnings (Before/After): %d / %d', [FMetricsBefore.Warnings, FMetricsAfter.Warnings]));
      LResult.AppendLine('');
      
      if (FMetricsBefore.ExeSizeBytes = 0) and (FMetricsAfter.ExeSizeBytes = 0) then
        LResult.AppendLine('Exe Size: Could not determine.');
        
      if (FMetricsBefore.ExeSizeBytes > 0) or (FMetricsAfter.ExeSizeBytes > 0) then
      begin
        LResult.AppendLine(Format('Exe Size (Before/After): %.1f MB / %.1f MB', [FMetricsBefore.ExeSizeBytes / (1024*1024), FMetricsAfter.ExeSizeBytes / (1024*1024)]));
        LSizeDelta := (FMetricsAfter.ExeSizeBytes - FMetricsBefore.ExeSizeBytes) / (1024.0 * 1024.0);
        if LSizeDelta < 0 then
          LResult.AppendLine(Format('Size Delta: %.2f MB smaller', [Abs(LSizeDelta)]));
        if LSizeDelta > 0 then
          LResult.AppendLine(Format('Size Delta: %.2f MB larger', [Abs(LSizeDelta)]));
        if SameValue(LSizeDelta, 0.0, 0.001) then
          LResult.AppendLine('Size Delta: 0 MB');
      end;
        
      LResult.AppendLine('');
    end;

    if FReportLines.Count > 0 then
    begin
      LResult.AppendLine('Atropos - Processing Report (Unit Dependency Issues)');
      LResult.AppendLine('========================================================');
      for LLine in FReportLines do
        LResult.AppendLine(LLine);
    end;

    Result := LResult.ToString;
  finally
    LResult.Free;
  end;
end;

function TReportGeneratorAdapter.GetReportContentHTML: string;
var
  LHtml: string;
  LMetricsHtml: string;
  LIssuesHtml: string;
  LItemHtml: string;
  LLine: string;
  LMode: string;
  LFileName: string;
  LIsFile: Boolean;
  LTimeDelta: Double;
  LSizeDelta: Double;
  LIssuesBuilder: TStringBuilder;
begin
  if (FReportLines.Count = 0) and not FHasMetrics then
    Exit('<html><head><title>Atropos Report</title></head><body style="background:#18181b; color:#fff; font-family: sans-serif; text-align:center; padding: 50px;"><h2>No files were processed.</h2></body></html>');

  LHtml := HTML_BASE_TEMPLATE;
  LHtml := LHtml.Replace('{{PROJECT_NAME}}', FProjectName);
  LHtml := LHtml.Replace('{{DELPHI_VERSION}}', IfThen(FHasMetrics, FMetricsBefore.DelphiVersion, 'Unknown'));
  
  LHtml := LHtml.Replace('{{ANALYSIS_TIME}}', FormatTimeMs(FAnalysisTimeMs));
    
  LHtml := LHtml.Replace('{{UNITS_ANALYZED}}', FUnitsAnalyzed.ToString);
  LHtml := LHtml.Replace('{{SEARCH_PATHS}}', FSearchPaths.ToString);

  if not FHasMetrics then
    LMetricsHtml := '        <div class="metric-card"><div class="metric-title">No metrics available</div></div>';

  if FHasMetrics then
  begin
    LTimeDelta := (FMetricsAfter.CompileTimeMs - FMetricsBefore.CompileTimeMs) / 1000.0;
    LSizeDelta := (FMetricsAfter.ExeSizeBytes - FMetricsBefore.ExeSizeBytes) / (1024.0 * 1024.0);
    
    LMetricsHtml := HTML_METRICS_TEMPLATE;
    LMetricsHtml := LMetricsHtml.Replace('{{CLEANED_COUNT}}', FMetricsAfter.RemovedUnitsCount.ToString);
    LMetricsHtml := LMetricsHtml.Replace('{{MOVED_COUNT}}', FMetricsAfter.MovedUnitsCount.ToString);
    LMetricsHtml := LMetricsHtml.Replace('{{HINTS_FIXED_COUNT}}', FMetricsAfter.ResolvedInlineHintsCount.ToString);
    
    LMetricsHtml := LMetricsHtml.Replace('{{COMPILE_TIME}}', FormatTimeMs(FMetricsAfter.CompileTimeMs));
    
    if SameValue(LTimeDelta, 0.0, 0.001) then
    begin
      LMetricsHtml := LMetricsHtml.Replace('{{TIME_COLOR}}', '');
      LMetricsHtml := LMetricsHtml.Replace('{{TIME_DELTA}}', '0s');
    end
    else if LTimeDelta < 0 then
    begin
      LMetricsHtml := LMetricsHtml.Replace('{{TIME_COLOR}}', 'delta-positive');
      LMetricsHtml := LMetricsHtml.Replace('{{TIME_DELTA}}', Format('%.2fs', [LTimeDelta]));
    end
    else if LTimeDelta > 0 then
    begin
      LMetricsHtml := LMetricsHtml.Replace('{{TIME_COLOR}}', 'delta-negative');
      LMetricsHtml := LMetricsHtml.Replace('{{TIME_DELTA}}', Format('+%.2fs', [LTimeDelta]));
    end;
    
    LMetricsHtml := LMetricsHtml.Replace('{{TIME_PCT}}', FormatDeltaPct(LTimeDelta / (FMetricsBefore.CompileTimeMs / 1000.0) * 100, True));
    
    if (FMetricsBefore.ExeSizeBytes = 0) and (FMetricsAfter.ExeSizeBytes = 0) then
    begin
      LMetricsHtml := LMetricsHtml.Replace('{{EXE_SIZE}}', '0.0');
      LMetricsHtml := LMetricsHtml.Replace('{{SIZE_COLOR}}', '');
      LMetricsHtml := LMetricsHtml.Replace('{{SIZE_DELTA}}', '0');
      LMetricsHtml := LMetricsHtml.Replace('{{SIZE_PCT}}', '');
    end;
    
    if (FMetricsBefore.ExeSizeBytes > 0) or (FMetricsAfter.ExeSizeBytes > 0) then
    begin
      LMetricsHtml := LMetricsHtml.Replace('{{EXE_SIZE}}', Format('%.1f', [FMetricsAfter.ExeSizeBytes / (1024.0 * 1024.0)]));
      
      if SameValue(LSizeDelta, 0.0, 0.01) then
      begin
        LMetricsHtml := LMetricsHtml.Replace('{{SIZE_COLOR}}', '');
        LMetricsHtml := LMetricsHtml.Replace('{{SIZE_DELTA}}', '0');
        LMetricsHtml := LMetricsHtml.Replace('{{SIZE_PCT}}', '');
      end
      else if LSizeDelta < 0 then
      begin
        LMetricsHtml := LMetricsHtml.Replace('{{SIZE_COLOR}}', 'delta-positive');
        LMetricsHtml := LMetricsHtml.Replace('{{SIZE_DELTA}}', Format('%.2f', [LSizeDelta]));
        LMetricsHtml := LMetricsHtml.Replace('{{SIZE_PCT}}', FormatDeltaPct(LSizeDelta / (FMetricsBefore.ExeSizeBytes / (1024.0*1024.0)) * 100, False));
      end
      else if LSizeDelta > 0 then
      begin
        LMetricsHtml := LMetricsHtml.Replace('{{SIZE_COLOR}}', 'delta-negative');
        LMetricsHtml := LMetricsHtml.Replace('{{SIZE_DELTA}}', Format('+%.2f', [LSizeDelta]));
        LMetricsHtml := LMetricsHtml.Replace('{{SIZE_PCT}}', FormatDeltaPct(LSizeDelta / (FMetricsBefore.ExeSizeBytes / (1024.0*1024.0)) * 100, False));
      end;
    end;
  end;

  LHtml := LHtml.Replace('{{METRICS_HTML}}', LMetricsHtml);

  if FReportLines.Count = 0 then
    LIssuesHtml := '        <p style="color: var(--text-muted); text-align: center; margin-top: 50px;">No unit modifications.</p>';

  if FReportLines.Count > 0 then
  begin
    LIssuesBuilder := TStringBuilder.Create;
    try
      LMode := EmptyStr;
      LIsFile := False;
      
      for LLine in FReportLines do
      begin
        if LLine.IsEmpty or LLine.Contains('Atropos - Processing Report') or LLine.Contains('=====') then
          Continue;
          
        if LLine.StartsWith('File:') then
        begin
          if LIsFile then
            LIssuesBuilder.AppendLine(HTML_ISSUE_TEMPLATE_END);

          LIsFile := True;
          LMode := EmptyStr;
          LFileName := LLine.Substring(5).Trim;
          
          LItemHtml := HTML_ISSUE_TEMPLATE_START;
          LItemHtml := LItemHtml.Replace('{{FILE_NAME}}', ExtractFileName(LFileName));
          LIssuesBuilder.AppendLine(LItemHtml);
          Continue;
        end;
        
        if LLine.Contains('Removed Uses:') then
        begin
          LMode := 'removed';
          Continue;
        end;
        
        if LLine.Contains('Moved to Implementation Uses:') then
        begin
          LMode := 'moved';
          Continue;
        end;
        
        if LLine.StartsWith('    -') then
        begin
          LItemHtml := HTML_ISSUE_ITEM_TEMPLATE;
          LItemHtml := LItemHtml.Replace('{{UNIT_NAME}}', LLine.Substring(6).Trim);
          
          if LMode = 'removed' then
          begin
            LItemHtml := LItemHtml.Replace('{{ICON_CLASS}}', 'icon-rm');
            LItemHtml := LItemHtml.Replace('{{ICON_CHAR}}', 'R');
            LItemHtml := LItemHtml.Replace('{{ACTION_NAME}}', 'Removed');
            LItemHtml := LItemHtml.Replace('{{IMPACT_DESC}}', 'Unused dependency cleaned');
          end;
          
          if LMode = 'moved' then
          begin
            LItemHtml := LItemHtml.Replace('{{ICON_CLASS}}', 'icon-mv');
            LItemHtml := LItemHtml.Replace('{{ICON_CHAR}}', 'M');
            LItemHtml := LItemHtml.Replace('{{ACTION_NAME}}', 'Moved');
            LItemHtml := LItemHtml.Replace('{{IMPACT_DESC}}', 'Moved to implementation');
          end;
          
          LIssuesBuilder.AppendLine(LItemHtml);
        end;
      end;
      
      if LIsFile then
        LIssuesBuilder.AppendLine(HTML_ISSUE_TEMPLATE_END);
      
      LIssuesHtml := LIssuesBuilder.ToString;
    finally
      LIssuesBuilder.Free;
    end;
  end;

  Result := LHtml.Replace('{{ISSUES_HTML}}', LIssuesHtml);
end;

end.
