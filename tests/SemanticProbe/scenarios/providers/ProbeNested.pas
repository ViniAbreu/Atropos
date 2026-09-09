unit ProbeNested;
interface
type TOuter = class
public
  type TNested = class end;
  type TKind = (InnerOne, InnerTwo);
  procedure Member;
end;
implementation
procedure TOuter.Member; begin end;
end.
