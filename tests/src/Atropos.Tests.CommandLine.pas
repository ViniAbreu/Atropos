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
    [Test]
    procedure ParsesDryRunOption;
    [Test]
    procedure ParsesRepeatedBuildTargets;
    [Test]
    procedure RejectsInvalidBuildTarget;
  end;

implementation

procedure TCommandLineParserTests.ParsesProjectAndAllOptions;
var
  LOptions: TCommandLineOptions;
begin
  LOptions := TCommandLineParser.Parse([
    '-dproj', 'Project.dproj', '--remove', '--move', '--debug', '-html', '-txt',
    '--output', 'reports']);
  Assert.IsTrue(LOptions.IsValid);
  Assert.AreEqual('Project.dproj', LOptions.ProjectPath);
  Assert.IsTrue(LOptions.Config.RemoveUnused);
  Assert.IsTrue(LOptions.Config.MoveToImplementation);
  Assert.IsTrue(LOptions.Config.EnableDebug);
  Assert.IsTrue(LOptions.Config.ExportHTML);
  Assert.IsTrue(LOptions.Config.ExportTXT);
  Assert.AreEqual('reports', LOptions.Config.OutputDirectory);
end;

procedure TCommandLineParserTests.RejectsMissingProjectAndMissingValue;
begin
  Assert.IsFalse(TCommandLineParser.Parse([]).IsValid);
  Assert.IsFalse(TCommandLineParser.Parse(['-dproj']).IsValid);
  Assert.IsFalse(TCommandLineParser.Parse(['--output']).IsValid);
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

procedure TCommandLineParserTests.ParsesDryRunOption;
var
  LOptions: TCommandLineOptions;
begin
  LOptions := TCommandLineParser.Parse(['-dproj', 'sample.dproj', '--dry-run']);
  Assert.IsTrue(LOptions.IsValid);
  Assert.IsTrue(LOptions.Config.DryRun);
end;

procedure TCommandLineParserTests.ParsesRepeatedBuildTargets;
var
  LOptions: TCommandLineOptions;
begin
  LOptions := TCommandLineParser.Parse(['-dproj', 'sample.dproj',
    '--target', 'Debug|Win32', '--target', 'Release|Win64']);
  Assert.IsTrue(LOptions.IsValid);
  Assert.AreEqual(2, Integer(Length(LOptions.Config.BuildTargets)));
  Assert.AreEqual('Debug', LOptions.Config.BuildTargets[0].Configuration);
  Assert.AreEqual('Win32', LOptions.Config.BuildTargets[0].Platform);
  Assert.AreEqual('Release', LOptions.Config.BuildTargets[1].Configuration);
  Assert.AreEqual('Win64', LOptions.Config.BuildTargets[1].Platform);
end;

procedure TCommandLineParserTests.RejectsInvalidBuildTarget;
begin
  Assert.IsFalse(TCommandLineParser.Parse(['-dproj', 'sample.dproj',
    '--target', 'Win64']).IsValid);
  Assert.IsFalse(TCommandLineParser.Parse(['-dproj', 'sample.dproj',
    '--target']).IsValid);
  Assert.IsFalse(TCommandLineParser.Parse(['-dproj', 'sample.dproj',
    '--target', 'Release" /t:Clean|Win64']).IsValid);
end;

initialization
  TDUnitX.RegisterTestFixture(TCommandLineParserTests);

end.
