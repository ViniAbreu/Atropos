program ContextRuntime;
{$APPTYPE CONSOLE}
uses System.SysUtils, Context.Consumer in 'Context.Consumer.pas', Mapped in 'chosen\Mapped.pas';
begin
  try
    Run;
  except
    on E: Exception do
    begin
      Writeln('ERROR:', E.ClassName, ':', E.Message);
      ExitCode := 1;
    end;
  end;
end.
