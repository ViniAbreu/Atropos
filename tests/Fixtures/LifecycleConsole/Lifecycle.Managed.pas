unit Lifecycle.Managed;
interface
type
  TTraceState = record
    class operator Initialize(out Dest: TTraceState);
    class operator Finalize(var Dest: TTraceState);
  end;
var State: TTraceState;
implementation
class operator TTraceState.Initialize(out Dest: TTraceState);
begin
  Writeln('RecordInit');
end;
class operator TTraceState.Finalize(var Dest: TTraceState);
begin
  Writeln('RecordFinal');
end;
end.
