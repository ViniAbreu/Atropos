unit Consumer;
interface
uses ProbeDep;
implementation
procedure Run(Value:TBase); begin with Value do Touch; end;
end.
