unit UnitA;

interface

uses
  System.SysUtils, System.Classes, UnitB; // This unit will be unused

type
  TMyClass = class
  public
    procedure DoSomething;
  end;

implementation

procedure TMyClass.DoSomething;
var
  LList: TStringList;
begin
  LList := TStringList.Create;
  try
    // Only use SysUtils (IntToStr) and Classes (TStringList)
    Writeln(IntToStr(10));
  finally
    LList.Free;
  end;
end;

end.
