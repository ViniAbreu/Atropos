unit Consumer;
interface
uses ProbeDep;
type TChild=class(TBase) public procedure Touch; override; end;
implementation
procedure TChild.Touch; begin inherited; end;
end.
