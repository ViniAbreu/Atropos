unit Atropos.Adapters.ReportGenerator;

interface
uses
  Atropos.Core.Ports, System.Generics.Collections;

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
uses
  System.SysUtils, System.Math, System.StrUtils;

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
  LMin, LSec, LMillis: Integer;
begin
  LMin := AMs div 60000;
  LSec := (AMs mod 60000) div 1000;
  LMillis := AMs mod 1000;
  Result := Format('%.2d:%.2d.%.3d', [LMin, LSec, LMillis]);
end;

function TReportGeneratorAdapter.GetReportContentTXT: string;
var
  LResult: TStringBuilder;
  LLine: string;
  LTimeDelta, LSizeDelta: Double;
begin
  if (FReportLines.Count = 0) and not FHasMetrics then
    Exit('No files were processed.');

  LResult := TStringBuilder.Create;
  try
    LResult.AppendLine('Atropos - Optimization Report');
    LResult.AppendLine('===============================');
    LResult.AppendLine('Project: ' + FProjectName);
    LResult.AppendLine('Analysis Time: ' + FormatTimeMs(FAnalysisTimeMs));
    LResult.AppendLine('Units Analyzed: ' + IntToStr(FUnitsAnalyzed));
    LResult.AppendLine('Search Paths: ' + IntToStr(FSearchPaths));
    LResult.AppendLine('');
    
    if FHasMetrics then
    begin
      LResult.AppendLine('Atropos - Metrics Report');
      LResult.AppendLine('===============================');
      LResult.AppendLine('Delphi Version: ' + FMetricsBefore.DelphiVersion);
      LResult.AppendLine('');
      LResult.AppendLine('Cleaned Units (Removed Uses): ' + IntToStr(FMetricsAfter.RemovedUnitsCount));
      LResult.AppendLine('Moved Units (To Implementation): ' + IntToStr(FMetricsAfter.MovedUnitsCount));
      LResult.AppendLine('');
      LResult.AppendLine('Compile Time (Before): ' + FormatTimeMs(FMetricsBefore.CompileTimeMs));
      LResult.AppendLine('Compile Time (After): ' + FormatTimeMs(FMetricsAfter.CompileTimeMs));
      
      LTimeDelta := (FMetricsAfter.CompileTimeMs - FMetricsBefore.CompileTimeMs) / 1000.0;
      if LTimeDelta < 0 then
        LResult.AppendLine('Delta Time: ' + Format('%.2fs faster', [Abs(LTimeDelta)]))
      else if LTimeDelta > 0 then
        LResult.AppendLine('Delta Time: ' + Format('%.2fs slower', [Abs(LTimeDelta)]))
      else
        LResult.AppendLine('Delta Time: 0s');
        
      LResult.AppendLine('');
      LResult.AppendLine(Format('Hints (Before/After): %d / %d', [FMetricsBefore.Hints, FMetricsAfter.Hints]));
      LResult.AppendLine(Format('Warnings (Before/After): %d / %d', [FMetricsBefore.Warnings, FMetricsAfter.Warnings]));
      LResult.AppendLine('');
      
      if (FMetricsBefore.ExeSizeBytes > 0) or (FMetricsAfter.ExeSizeBytes > 0) then
      begin
        LResult.AppendLine(Format('Exe Size (Before/After): %.1f MB / %.1f MB', [FMetricsBefore.ExeSizeBytes / (1024*1024), FMetricsAfter.ExeSizeBytes / (1024*1024)]));
        LSizeDelta := (FMetricsAfter.ExeSizeBytes - FMetricsBefore.ExeSizeBytes) / (1024.0 * 1024.0);
        if LSizeDelta < 0 then
          LResult.AppendLine(Format('Size Delta: %.2f MB smaller', [Abs(LSizeDelta)]))
        else if LSizeDelta > 0 then
          LResult.AppendLine(Format('Size Delta: %.2f MB larger', [Abs(LSizeDelta)]))
        else
          LResult.AppendLine('Size Delta: 0 MB');
      end
      else
        LResult.AppendLine('Exe Size: Could not determine.');
        
      LResult.AppendLine('');
    end;

    if FReportLines.Count > 0 then
    begin
      LResult.AppendLine('Atropos - Processing Report (Unit Dependency Issues)');
      LResult.AppendLine('===============================');
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
  LResult: TStringBuilder;
  LLine, LMode, LFileName: string;
  LIsFile: Boolean;
  LTimeDelta, LSizeDelta: Double;
  
  function FormatDeltaPct(ADiff: Double; ALowerIsBetter: Boolean): string;
  begin
    if SameValue(ADiff, 0.0, 0.001) then
      Result := ''
    else if ADiff < 0 then
      Result := Format(' (%.1f%% %s)', [Abs(ADiff), IfThen(ALowerIsBetter, 'faster', 'smaller')])
    else
      Result := Format(' (%.1f%% %s)', [Abs(ADiff), IfThen(ALowerIsBetter, 'slower', 'larger')]);
  end;

begin
  if (FReportLines.Count = 0) and not FHasMetrics then
    Exit('<html><head><title>Atropos Report</title></head><body style="background:#18181b; color:#fff; font-family: sans-serif; text-align:center; padding: 50px;"><h2>No files were processed.</h2></body></html>');

  LResult := TStringBuilder.Create;
  try
    LResult.AppendLine('<!DOCTYPE html>');
    LResult.AppendLine('<html lang="en">');
    LResult.AppendLine('<head>');
    LResult.AppendLine('  <meta charset="UTF-8">');
    LResult.AppendLine('  <meta name="viewport" content="width=device-width, initial-scale=1.0">');
    LResult.AppendLine('  <title>Atropos - Report</title>');
    LResult.AppendLine('  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">');
    LResult.AppendLine('  <style>');
    LResult.AppendLine('    :root { --bg-body: #18181b; --bg-nav: #27272a; --bg-card: #27272a; --border: #3f3f46; --text-main: #f4f4f5; --text-muted: #a1a1aa; --accent-blue: #38bdf8; --status-passed: #22c55e; --status-failed: #ef4444; --issue-removed: #ef4444; --issue-moved: #f59e0b; }');
    LResult.AppendLine('    body { font-family: "Inter", sans-serif; background-color: var(--bg-body); color: var(--text-main); margin: 0; padding: 0; line-height: 1.5; height: 100vh; display: flex; flex-direction: column; overflow: hidden; }');
    LResult.AppendLine('    * { box-sizing: border-box; }');
    LResult.AppendLine('    .navbar { background-color: var(--bg-nav); border-bottom: 1px solid var(--border); padding: 12px 24px; display: flex; align-items: center; gap: 25px; flex-shrink: 0; }');
    LResult.AppendLine('    .navbar-logo { font-weight: 700; font-size: 1.2rem; color: var(--accent-blue); letter-spacing: -0.5px; }');
    LResult.AppendLine('    .navbar-item { color: var(--text-main); font-size: 0.9rem; font-weight: 500; text-transform: uppercase; letter-spacing: 1px; cursor: pointer; border-bottom: 2px solid var(--accent-blue); padding-bottom: 4px; }');
    LResult.AppendLine('    .container { width: 100%; max-width: 1200px; margin: 0 auto; padding: 30px 24px; display: flex; flex-direction: column; flex: 1; overflow: hidden; }');
    LResult.AppendLine('    .header-title { font-size: 1.8rem; font-weight: 600; margin: 0 0 5px 0; flex-shrink: 0; }');
    LResult.AppendLine('    .header-subtitle { color: var(--text-muted); font-size: 0.9rem; margin-bottom: 30px; flex-shrink: 0; }');
    LResult.AppendLine('    .dashboard-top { display: flex; gap: 20px; margin-bottom: 30px; flex-shrink: 0; }');
    LResult.AppendLine('    .info-card { background-color: var(--bg-card); border: 1px solid var(--border); border-radius: 4px; padding: 20px; flex: 1.5; display: flex; flex-direction: column; justify-content: center; border-left: 4px solid var(--accent-blue); }');
    LResult.AppendLine('    .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; }');
    LResult.AppendLine('    .info-item { display: flex; flex-direction: column; }');
    LResult.AppendLine('    .info-label { font-size: 0.75rem; text-transform: uppercase; color: var(--text-muted); font-weight: 600; margin-bottom: 4px; }');
    LResult.AppendLine('    .info-value { font-size: 1.1rem; font-weight: 600; color: var(--text-main); }');
    LResult.AppendLine('    .metrics-grid { display: flex; flex: 3; gap: 15px; }');
    LResult.AppendLine('    .metric-card { background-color: var(--bg-card); border: 1px solid var(--border); border-radius: 4px; padding: 20px; flex: 1; display: flex; flex-direction: column; }');
    LResult.AppendLine('    .metric-title { font-size: 0.85rem; color: var(--text-muted); font-weight: 500; margin-bottom: 15px; display: flex; align-items: center; gap: 8px; }');
    LResult.AppendLine('    .metric-value { font-size: 1.8rem; font-weight: 600; color: var(--text-main); }');
    LResult.AppendLine('    .metric-delta { font-size: 0.85rem; margin-top: 5px; }');
    LResult.AppendLine('    .delta-positive { color: var(--status-passed); }');
    LResult.AppendLine('    .delta-negative { color: var(--status-failed); }');
    LResult.AppendLine('    .issues-section { display: flex; flex-direction: column; flex: 1; overflow: hidden; }');
    LResult.AppendLine('    .issues-section-title { font-size: 1.2rem; font-weight: 600; margin-bottom: 15px; padding-bottom: 10px; border-bottom: 1px solid var(--border); flex-shrink: 0; }');
    LResult.AppendLine('    .issue-list { display: flex; flex-direction: column; gap: 10px; overflow-y: auto; padding-right: 10px; }');
    LResult.AppendLine('    ::-webkit-scrollbar { width: 8px; }');
    LResult.AppendLine('    ::-webkit-scrollbar-track { background: transparent; }');
    LResult.AppendLine('    ::-webkit-scrollbar-thumb { background: #3f3f46; border-radius: 4px; }');
    LResult.AppendLine('    ::-webkit-scrollbar-thumb:hover { background: #52525b; }');
    LResult.AppendLine('    .issue-item { background-color: var(--bg-card); border: 1px solid var(--border); border-radius: 4px; transition: border-color 0.2s; }');
    LResult.AppendLine('    .issue-item:hover { border-color: #52525b; }');
    LResult.AppendLine('    .issue-summary { padding: 12px 16px; cursor: pointer; display: flex; align-items: center; gap: 15px; user-select: none; }');
    LResult.AppendLine('    .issue-summary::-webkit-details-marker { display: none; }');
    LResult.AppendLine('    .issue-icon { font-size: 1.2rem; color: var(--text-muted); transition: transform 0.2s; }');
    LResult.AppendLine('    details[open] .issue-icon { transform: rotate(90deg); }');
    LResult.AppendLine('    .issue-file { font-family: "Consolas", "JetBrains Mono", monospace; font-size: 0.95rem; font-weight: 500; flex: 1; }');
    LResult.AppendLine('    .issue-badges { display: flex; gap: 8px; }');
    LResult.AppendLine('    .badge { font-size: 0.75rem; padding: 2px 8px; border-radius: 12px; font-weight: 600; color: #fff; }');
    LResult.AppendLine('    .badge-removed { background-color: var(--issue-removed); }');
    LResult.AppendLine('    .badge-moved { background-color: var(--issue-moved); }');
    LResult.AppendLine('    .issue-details { padding: 15px; border-top: 1px solid var(--border); background-color: rgba(0,0,0,0.15); animation: fadeIn 0.3s ease; }');
    LResult.AppendLine('    @keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }');
    LResult.AppendLine('    .uses-table { width: 100%; border-collapse: collapse; font-family: "Consolas", "JetBrains Mono", monospace; font-size: 0.85rem; }');
    LResult.AppendLine('    .uses-table th { text-align: left; padding: 8px; color: var(--text-muted); border-bottom: 1px solid var(--border); font-weight: 500; }');
    LResult.AppendLine('    .uses-table td { padding: 8px; border-bottom: 1px solid var(--border); }');
    LResult.AppendLine('    .uses-table tr:last-child td { border-bottom: none; }');
    LResult.AppendLine('    .type-icon { display: inline-block; width: 16px; height: 16px; border-radius: 50%; text-align: center; line-height: 16px; font-size: 10px; color: white; margin-right: 8px; }');
    LResult.AppendLine('    .icon-rm { background-color: var(--issue-removed); }');
    LResult.AppendLine('    .icon-mv { background-color: var(--issue-moved); }');
    LResult.AppendLine('  </style>');
    LResult.AppendLine('</head>');
    LResult.AppendLine('<body>');
    
    LResult.AppendLine('  <div class="navbar">');
    LResult.AppendLine('    <div class="navbar-logo">ATROPOS</div>');
    LResult.AppendLine('    <div class="navbar-item">Overview</div>');
    LResult.AppendLine('  </div>');
    
    LResult.AppendLine('  <div class="container">');
    LResult.AppendLine('    <h1 class="header-title">Optimization Report</h1>');
    LResult.AppendLine('    <div class="header-subtitle">Analysis finished successfully &bull; Project: ' + FProjectName + '</div>');
    
    LResult.AppendLine('    <div class="dashboard-top">');
    
    // Info block
    LResult.AppendLine('      <div class="info-card">');
    LResult.AppendLine('        <div class="info-grid">');
    LResult.AppendLine('          <div class="info-item"><span class="info-label">Delphi Version</span><span class="info-value">' + IfThen(FHasMetrics, FMetricsBefore.DelphiVersion, 'Unknown') + '</span></div>');
    LResult.AppendLine('          <div class="info-item"><span class="info-label">Analysis Time</span><span class="info-value">' + FormatTimeMs(FAnalysisTimeMs) + '</span></div>');
    LResult.AppendLine('          <div class="info-item"><span class="info-label">Units Analyzed</span><span class="info-value">' + IntToStr(FUnitsAnalyzed) + '</span></div>');
    LResult.AppendLine('          <div class="info-item"><span class="info-label">Search Paths</span><span class="info-value">' + IntToStr(FSearchPaths) + '</span></div>');
    LResult.AppendLine('        </div>');
    LResult.AppendLine('      </div>');
    
    // Metrics grid
    LResult.AppendLine('      <div class="metrics-grid">');
    if FHasMetrics then
    begin
      LResult.AppendLine('        <div class="metric-card">');
      LResult.AppendLine('          <div class="metric-title">Cleaned Units</div>');
      LResult.AppendLine('          <div class="metric-value">' + IntToStr(FMetricsAfter.RemovedUnitsCount) + '</div>');
      LResult.AppendLine('          <div class="metric-delta delta-positive">' + IntToStr(FMetricsAfter.RemovedUnitsCount) + ' uses removed</div>');
      LResult.AppendLine('        </div>');
      
      LResult.AppendLine('        <div class="metric-card">');
      LResult.AppendLine('          <div class="metric-title">Moved Units</div>');
      LResult.AppendLine('          <div class="metric-value">' + IntToStr(FMetricsAfter.MovedUnitsCount) + '</div>');
      LResult.AppendLine('          <div class="metric-delta delta-positive">' + IntToStr(FMetricsAfter.MovedUnitsCount) + ' moved to implementation</div>');
      LResult.AppendLine('        </div>');
      
      LTimeDelta := (FMetricsAfter.CompileTimeMs - FMetricsBefore.CompileTimeMs) / 1000.0;
      LSizeDelta := (FMetricsAfter.ExeSizeBytes - FMetricsBefore.ExeSizeBytes) / (1024.0 * 1024.0);
      
      LResult.AppendLine('        <div class="metric-card">');
      LResult.AppendLine('          <div class="metric-title">Compile Time</div>');
      LResult.AppendLine('          <div class="metric-value">' + FormatTimeMs(FMetricsAfter.CompileTimeMs) + '</div>');
      
      if LTimeDelta < 0 then
        LResult.AppendLine('          <div class="metric-delta delta-positive">' + Format('%.2fs', [LTimeDelta]) + FormatDeltaPct(LTimeDelta / (FMetricsBefore.CompileTimeMs / 1000.0) * 100, True) + '</div>')
      else if LTimeDelta > 0 then
        LResult.AppendLine('          <div class="metric-delta delta-negative">+' + Format('%.2fs', [LTimeDelta]) + FormatDeltaPct(LTimeDelta / (FMetricsBefore.CompileTimeMs / 1000.0) * 100, True) + '</div>')
      else
        LResult.AppendLine('          <div class="metric-delta">0s</div>');
      LResult.AppendLine('        </div>');
      
      if (FMetricsBefore.ExeSizeBytes > 0) or (FMetricsAfter.ExeSizeBytes > 0) then
      begin
        LResult.AppendLine('        <div class="metric-card">');
        LResult.AppendLine('          <div class="metric-title">Exe Size</div>');
        LResult.AppendLine('          <div class="metric-value">' + Format('%.1f', [FMetricsAfter.ExeSizeBytes / (1024.0 * 1024.0)]) + ' <span style="font-size:1rem; color:var(--text-muted)">MB</span></div>');
        if LSizeDelta < 0 then
          LResult.AppendLine('          <div class="metric-delta delta-positive">' + Format('%.2f MB', [LSizeDelta]) + FormatDeltaPct(LSizeDelta / (FMetricsBefore.ExeSizeBytes / (1024.0*1024.0)) * 100, True) + '</div>')
        else if LSizeDelta > 0 then
          LResult.AppendLine('          <div class="metric-delta delta-negative">+' + Format('%.2f MB', [LSizeDelta]) + FormatDeltaPct(LSizeDelta / (FMetricsBefore.ExeSizeBytes / (1024.0*1024.0)) * 100, True) + '</div>')
        else
          LResult.AppendLine('          <div class="metric-delta">0 MB</div>');
        LResult.AppendLine('        </div>');
      end;
    end
    else
      LResult.AppendLine('        <div class="metric-card"><div class="metric-title">No metrics available</div></div>');
      
    LResult.AppendLine('      </div>'); // metrics-grid
    LResult.AppendLine('    </div>'); // dashboard-top
    
    LResult.AppendLine('    <div class="issues-section">');
    LResult.AppendLine('      <div class="issues-section-title">Unit Dependency Issues (Resolved)</div>');
    LResult.AppendLine('      <div class="issue-list">');
    
    if FReportLines.Count > 0 then
    begin
      LMode := '';
      LIsFile := False;
      
      for LLine in FReportLines do
      begin
        if (LLine = '') or (Pos('Atropos - Processing Report', LLine) > 0) or (Pos('=====', LLine) > 0) then
          Continue;
          
        if Pos('File:', LLine) = 1 then
        begin
          if LIsFile then LResult.AppendLine('              </tbody></table></div></details>');
          LIsFile := True;
          LMode := '';
          LFileName := Trim(Copy(LLine, 6, Length(LLine)));
          LResult.AppendLine('        <details class="issue-item">');
          LResult.AppendLine('          <summary class="issue-summary">');
          LResult.AppendLine('            <div class="issue-icon">&#9654;</div>');
          LResult.AppendLine('            <div class="issue-file">' + ExtractFileName(LFileName) + '</div>');
          LResult.AppendLine('          </summary>');
          LResult.AppendLine('          <div class="issue-details">');
          LResult.AppendLine('            <table class="uses-table">');
          LResult.AppendLine('              <thead><tr><th width="150">Action</th><th>Unit Name</th><th>Impact</th></tr></thead>');
          LResult.AppendLine('              <tbody>');
        end
        else if Pos('Removed Uses:', LLine) > 0 then
          LMode := 'removed'
        else if Pos('Moved to Implementation Uses:', LLine) > 0 then
          LMode := 'moved'
        else if Pos('    -', LLine) = 1 then
        begin
          if LMode = 'removed' then
          begin
            LResult.AppendLine('                <tr>');
            LResult.AppendLine('                  <td><span class="type-icon icon-rm">R</span> Removed</td>');
            LResult.AppendLine('                  <td>' + Trim(Copy(LLine, 7, Length(LLine))) + '</td>');
            LResult.AppendLine('                  <td style="color:var(--text-muted)">Unused dependency cleaned</td>');
            LResult.AppendLine('                </tr>');
          end
          else if LMode = 'moved' then
          begin
            LResult.AppendLine('                <tr>');
            LResult.AppendLine('                  <td><span class="type-icon icon-mv">M</span> Moved</td>');
            LResult.AppendLine('                  <td>' + Trim(Copy(LLine, 7, Length(LLine))) + '</td>');
            LResult.AppendLine('                  <td style="color:var(--text-muted)">Moved to implementation</td>');
            LResult.AppendLine('                </tr>');
          end;
        end;
      end;
      
      if LIsFile then LResult.AppendLine('              </tbody></table></div></details>');
    end
    else
      LResult.AppendLine('        <p style="color: var(--text-muted); text-align: center; margin-top: 50px;">No unit modifications.</p>');

    LResult.AppendLine('      </div>'); // issue-list
    LResult.AppendLine('    </div>'); // issues-section
    
    LResult.AppendLine('  </div>'); // container
    LResult.AppendLine('</body>');
    LResult.AppendLine('</html>');

    Result := LResult.ToString;
  finally
    LResult.Free;
  end;
end;

end.
