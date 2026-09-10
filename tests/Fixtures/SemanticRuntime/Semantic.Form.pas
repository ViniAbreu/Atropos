unit Semantic.Form;
interface
uses System.Classes, Vcl.Forms, Semantic.Registration, Semantic.Unused;
type
  TSemanticForm = class(TForm)
    procedure FormCreate(Sender: TObject);
  end;
procedure RunForm;
implementation
uses System.SysUtils;
{$R *.dfm}
procedure TSemanticForm.FormCreate(Sender: TObject);
var Child: TComponent;
begin
  Child := FindComponent('DynamicProbe');
  if not Assigned(Child) or (Child.Tag <> 41) then
    raise Exception.Create('DFM child was not streamed.');
  Child.Tag := Child.Tag + 1;
end;
procedure RunForm;
var Form: TSemanticForm; Registered: TPersistentClass;
begin
  Form := TSemanticForm.Create(nil);
  try
    if Form.FindComponent('DynamicProbe').Tag <> 42 then
      raise Exception.Create('DFM OnCreate method was not bound.');
    Writeln('DFM:', Form.FindComponent('DynamicProbe').Tag);
    Registered := GetClass('TStreamProbe');
    if not Assigned(Registered) then
      raise Exception.Create('String class registration was lost.');
    Writeln('Registry:', Registered.ClassName);
  finally
    Form.Free;
  end;
end;
end.
