program SemanticRuntime;
{$APPTYPE CONSOLE}
uses System.SysUtils, Vcl.Forms,
  Semantic.Form in 'Semantic.Form.pas', Semantic.Calls in 'Semantic.Calls.pas',
  Semantic.HelperCalls in 'Semantic.HelperCalls.pas';
begin
  try
    Application.Initialize;
    RunForm;
    RunCalls;
    RunHelpers;
  except
    on E: Exception do
    begin
      Writeln('ERROR:', E.ClassName, ':', E.Message);
      ExitCode := 3;
    end;
  end;
end.
