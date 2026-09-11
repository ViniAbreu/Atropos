program BinaryRuntime;
{$APPTYPE CONSOLE}
uses System.SysUtils, Binary.Consumer in 'Binary.Consumer.pas';
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
