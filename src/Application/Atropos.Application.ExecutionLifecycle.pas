unit Atropos.Application.ExecutionLifecycle;

interface

type
  TExecutionLifecycle = class
  private
    FRunning: Boolean;
  public
    function TryBegin: Boolean;
    procedure Complete;
    function CanClose: Boolean;
    property Running: Boolean read FRunning;
  end;

implementation

function TExecutionLifecycle.TryBegin: Boolean;
begin
  Result := not FRunning;
  if Result then
    FRunning := True;
end;

procedure TExecutionLifecycle.Complete;
begin
  FRunning := False;
end;

function TExecutionLifecycle.CanClose: Boolean;
begin
  Result := not FRunning;
end;

end.
