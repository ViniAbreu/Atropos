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

initialization
  TDUnitX.RegisterTestFixture(TReportGeneratorTests);

end.

