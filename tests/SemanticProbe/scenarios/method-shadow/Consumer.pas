unit Consumer;
interface
uses ProbeDep;
type TLocal = class procedure CallMe; end;
implementation
procedure TLocal.CallMe; begin end;
end.
