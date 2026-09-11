unit Edit.Consumer;
interface
uses Edit.Value, Edit.Unused;
procedure Run;
implementation
(*$IFDEF WITH_EXTRA*)
uses Edit.Extra;
(*$ENDIF*)
procedure Run;
begin
  Writeln(GetValue);
end;
end.
