unit Semantic.HelperCalls;
interface
uses Semantic.FirstHelper, Semantic.SecondHelper, Semantic.Unused;
procedure RunHelpers;
implementation
procedure RunHelpers;
var
  Value: string;
begin
  Value := 'value';
  Writeln(Value.SelectedHelper);
end;
end.
