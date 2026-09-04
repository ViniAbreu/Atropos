unit Atropos.Tests.ReportGenerator;

interface
uses
  Atropos.Core.Ports, Atropos.Adapters.ReportGenerator, DUnitX.TestFramework, System.SysUtils;

type
  [TestFixture]
  TReportGeneratorTests = class
  private
    FReport: IReportGenerator;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    
    [Test]
    [TestCase('Generate report content', 'Should generate a valid analysis report')]
    procedure Test_GenerateReportContent;
    
    [Test]
    [TestCase('No changes', 'Should not modify the file if no issues are detected')]
    procedure Test_NoChanges;
    [Test]
    procedure ImprovedMetricsAreRenderedInTextAndHTML;
    [Test]
    procedure RegressedMetricsAreRenderedInTextAndHTML;
    [Test]
    procedure HTMLWithoutMetricsStillRendersIssues;
  end;

implementation

procedure TReportGeneratorTests.Setup;
begin
  FReport := TReportGeneratorAdapter.Create;
end;

procedure TReportGeneratorTests.TearDown;
begin
  FReport := nil;
end;

procedure TReportGeneratorTests.Test_GenerateReportContent;
var
  LResult: string;
begin
  FReport.AddUnitProcessed('Unit1.pas', ['SysUtils'], ['Classes']);
  FReport.AddUnitProcessed('Unit2.pas', [], []);
  FReport.AddUnitProcessed('Unit3.pas', ['Windows'], []);
  
  LResult := FReport.GetReportContentTXT;
  
  Assert.IsTrue(LResult.Contains('File: Unit1.pas'));
  Assert.IsTrue(LResult.Contains('  Removed Uses:'));
  Assert.IsTrue(LResult.Contains('    - SysUtils'));
  Assert.IsTrue(LResult.Contains('  Moved to Implementation Uses:'));
  Assert.IsTrue(LResult.Contains('    - Classes'));
  
  Assert.IsFalse(LResult.Contains('File: Unit2.pas'), 'Empty changes should not be printed');
  
  Assert.IsTrue(LResult.Contains('File: Unit3.pas'));
  Assert.IsTrue(LResult.Contains('    - Windows'));
end;

procedure TReportGeneratorTests.Test_NoChanges;
var
  LResult: string;
begin
  FReport.AddUnitProcessed('CleanUnit.pas', [], []);
  LResult := FReport.GetReportContentTXT;
  Assert.IsTrue(LResult.Contains('No files were processed.'));
end;

procedure TReportGeneratorTests.ImprovedMetricsAreRenderedInTextAndHTML;
var
  LBefore: TBuildMetrics;
  LAfter: TBuildMetrics;
  LText: string;
  LHTML: string;
begin
  LBefore := Default(TBuildMetrics);
  LAfter := Default(TBuildMetrics);
  LBefore.DelphiVersion := '12.3';
  LBefore.CompileTimeMs := 2000;
  LBefore.ExeSizeBytes := 2 * 1024 * 1024;
  LBefore.Hints := 4;
  LAfter.CompileTimeMs := 1000;
  LAfter.ExeSizeBytes := 1024 * 1024;
  LAfter.Hints := 1;
  LAfter.RemovedUnitsCount := 2;
  LAfter.MovedUnitsCount := 1;
  LAfter.ResolvedInlineHintsCount := 3;
  FReport.SetAnalysisInfo('Project.dproj', 1250, 10, 4);
  FReport.AddMetrics(LBefore, LAfter);
  FReport.AddUnitProcessed('Unit1.pas', ['Unused.Unit'], ['Moved.Unit']);

  LText := FReport.GetReportContentTXT;
  LHTML := FReport.GetReportContentHTML;
  Assert.IsTrue(LText.Contains('faster'));
  Assert.IsTrue(LText.Contains('smaller'));
  Assert.IsTrue(LHTML.Contains('delta-positive'));
  Assert.IsTrue(LHTML.Contains('Unused.Unit'));
  Assert.IsTrue(LHTML.Contains('Moved.Unit'));
end;

procedure TReportGeneratorTests.RegressedMetricsAreRenderedInTextAndHTML;
var
  LBefore: TBuildMetrics;
  LAfter: TBuildMetrics;
  LText: string;
  LHTML: string;
begin
  LBefore := Default(TBuildMetrics);
  LAfter := Default(TBuildMetrics);
  LBefore.CompileTimeMs := 1000;
  LBefore.ExeSizeBytes := 1024 * 1024;
  LAfter.CompileTimeMs := 2000;
  LAfter.ExeSizeBytes := 2 * 1024 * 1024;
  FReport.AddMetrics(LBefore, LAfter);

  LText := FReport.GetReportContentTXT;
  LHTML := FReport.GetReportContentHTML;
  Assert.IsTrue(LText.Contains('slower'));
  Assert.IsTrue(LText.Contains('larger'));
  Assert.IsTrue(LHTML.Contains('delta-negative'));
  Assert.IsTrue(LHTML.Contains('No unit modifications.'));
end;

procedure TReportGeneratorTests.HTMLWithoutMetricsStillRendersIssues;
var
  LHTML: string;
begin
  FReport.SetAnalysisInfo('Project.dproj', 0, 1, 1);
  FReport.AddUnitProcessed('Unit1.pas', ['Unused.Unit'], []);
  LHTML := FReport.GetReportContentHTML;
  Assert.IsTrue(LHTML.Contains('No metrics available'));
  Assert.IsTrue(LHTML.Contains('Unused.Unit'));
end;

initialization
  TDUnitX.RegisterTestFixture(TReportGeneratorTests);

end.

