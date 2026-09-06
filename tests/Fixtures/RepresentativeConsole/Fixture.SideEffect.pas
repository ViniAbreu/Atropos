unit Fixture.SideEffect;

interface

implementation

var
  SideEffectState: Integer;

initialization
  SideEffectState := 1;

finalization
  SideEffectState := 0;

end.
