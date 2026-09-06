unit Fixture.Main;

interface

procedure Run;

implementation

uses
  System.SysUtils,
  {$IFDEF DEBUG}
  Fixture.Conditional,
  {$ENDIF}
  Fixture.Aliased,
  Fixture.SideEffect,
  Fixture.Unused;

procedure Run;
begin
  Writeln(TAliased.Value);
  {$IFDEF DEBUG}
  TConditional.Touch;
  {$ENDIF}
end;

end.
