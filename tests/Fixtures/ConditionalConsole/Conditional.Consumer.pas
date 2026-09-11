unit Conditional.Consumer;
interface
{$I state.inc}
uses
  {$IF (DEFINED(WITH_CHOSEN) AND NOT DEFINED(ABSENT))}
  Conditional.Chosen,
  {$ELSE}
  Conditional.Other,
  {$IFEND}
  Conditional.Always, Conditional.Unused;
procedure Run;
implementation
procedure Run;
begin
  {$IF FALSE AND TRUE = FALSE}
  Writeln('Precedence');
  {$IFEND}
  {$IFOPT R+}
  Writeln(SelectedValue + BaseValue);
  {$ELSE}
  Writeln('WrongSwitch');
  {$ENDIF}
  {$IF FALSE}
  Writeln('WrongBranch');
  {$ELSEIF DEFINED(FROM_INCLUDE)}
  Writeln('Include');
  {$ELSEIF TRUE}
  Writeln('WrongElseIf');
  {$IFEND}
end;
end.
