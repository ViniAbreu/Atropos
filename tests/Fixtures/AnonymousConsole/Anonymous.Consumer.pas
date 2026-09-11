unit Anonymous.Consumer;
interface
uses Anonymous.Shadow, Anonymous.Global;
procedure Run;
implementation
type
  TParamAction = reference to procedure(Clash: Integer);
  TCaptureAction = reference to procedure;
procedure Run;
var ParamAction: TParamAction; CaptureAction: TCaptureAction; LocalTotal: Integer;
begin
  LocalTotal := 10;
  ParamAction := procedure(Clash: Integer)
    begin
      Inc(Clash);
      Writeln('Parameter:', Clash);
    end;
  CaptureAction := procedure
    begin
      Inc(LocalTotal);
      Inc(Shared);
      Writeln('Capture:', LocalTotal);
    end;
  ParamAction(1);
  CaptureAction();
  Writeln('Global:', Shared);
end;
end.
