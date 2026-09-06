program RepresentativeVCL;

uses
  Vcl.Forms,
  Fixture.VclMain in 'Fixture.VclMain.pas' {FixtureForm},
  Fixture.VclUnused in 'Fixture.VclUnused.pas';

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TFixtureForm, FixtureForm);
  Application.Run;
end.
