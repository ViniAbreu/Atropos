unit Atropos.Tests.CommandLine;

interface

uses
  Atropos.Application.CommandLine,
  DUnitX.TestFramework,
  System.SysUtils;

type
  [TestFixture]
  TCommandLineParserTests = class
  public
    [Test]
    procedure ParsesProjectAndAllOptions;
    [Test]
    procedure RejectsMissingProjectAndMissingValue;
    [Test]
    procedure RejectsUnknownOption;
    [Test]
    procedure HelpDoesNotRequireProject;
  end;

implementation

procedure TCommandLineParserTests.ParsesProjectAndAllOptions;
var
  LOptions: TCommandLineOptions;
begin
  LOptions := TCommandLineParser.Parse([
    '-dproj', 'Project.dproj', '--remove', '--move', '--debug', '-html', '-txt']);
  Assert.IsTrue(LOptions.IsValid);
  Assert.AreEqual('Project.dproj', LOptions.ProjectPath);
  Assert.IsTrue(LOptions.Config.RemoveUnused);
  Assert.IsTrue(LOptions.Config.MoveToImplementation);
  Assert.IsTrue(LOptions.Config.EnableDebug);
  Assert.IsTrue(LOptions.Config.ExportHTML);
  Assert.IsTrue(LOptions.Config.ExportTXT);
end;

procedure TCommandLineParserTests.RejectsMissingProjectAndMissingValue;
begin
  Assert.IsFalse(TCommandLineParser.Parse([]).IsValid);
  Assert.IsFalse(TCommandLineParser.Parse(['-dproj']).IsValid);
end;

procedure TCommandLineParserTests.RejectsUnknownOption;
var
  LOptions: TCommandLineOptions;
begin
  LOptions := TCommandLineParser.Parse(['--unknown']);
  Assert.IsFalse(LOptions.IsValid);
  Assert.IsTrue(LOptions.ErrorMessage.Contains('--unknown'));
end;

procedure TCommandLineParserTests.HelpDoesNotRequireProject;
var
  LOptions: TCommandLineOptions;
begin
  LOptions := TCommandLineParser.Parse(['--help']);
  Assert.IsTrue(LOptions.IsValid);
  Assert.IsTrue(LOptions.ShowHelp);
end;

initialization
  TDUnitX.RegisterTestFixture(TCommandLineParserTests);

end.
