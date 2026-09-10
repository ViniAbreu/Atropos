program AnonymousConsole;
{$APPTYPE CONSOLE}
uses Anonymous.Consumer in 'Anonymous.Consumer.pas', Anonymous.Leak in 'Anonymous.Leak.pas';
begin
  Run;
  RunLeak;
end.
