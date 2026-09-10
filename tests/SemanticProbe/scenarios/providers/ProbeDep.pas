unit ProbeDep;
interface
type
  TItem = class end;
  TBase = class
  public
    procedure Touch; virtual;
  end;
  TRec = record Value: Integer; end;
  IThing = interface procedure Ping; end;
  EProbe = class(TObject) end;
  TCallback = procedure;
const Limit = 7;
var Clash: Integer; GlobalValue: Integer;
resourcestring TextValue = 'text';
procedure CallMe;
procedure Boot;
procedure Shutdown;
implementation
procedure TBase.Touch; begin end;
procedure CallMe; begin end;
procedure Boot; begin end;
procedure Shutdown; begin end;
end.
