unit Lifecycle.Provider;
interface
procedure Boot;
procedure Shutdown;
implementation
procedure Boot;
begin
  Writeln('Boot');
end;
procedure Shutdown;
begin
  Writeln('Shutdown');
end;
end.