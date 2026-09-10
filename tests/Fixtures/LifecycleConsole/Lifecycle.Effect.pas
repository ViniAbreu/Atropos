unit Lifecycle.Effect;
interface
implementation
initialization
  Writeln('TransitiveInit');
finalization
  Writeln('TransitiveFinal');
end.