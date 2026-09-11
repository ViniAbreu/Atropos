unit Semantic.Registration;
interface
uses System.Classes;
type TStreamProbe = class(TComponent) end;
implementation
initialization
  RegisterClass(TStreamProbe);
finalization
  UnRegisterClass(TStreamProbe);
end.
