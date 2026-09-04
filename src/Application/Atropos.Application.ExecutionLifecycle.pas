unit Atropos.Application.ExecutionLifecycle;

interface

uses
  System.SyncObjs;

type
  TExecutionLifecycle = class
  private
    FRunning: Boolean;
    FCancelRequested: Integer;
  public
    function TryBegin: Boolean;
    procedure Complete;
    procedure RequestCancel;
    function IsCancellationRequested: Boolean;
    function CanClose: Boolean;
    property Running: Boolean read FRunning;
  end;

implementation

function TExecutionLifecycle.TryBegin: Boolean;
begin
  Result := not FRunning;
  if Result then
  begin
    TInterlocked.Exchange(FCancelRequested, 0);
    FRunning := True;
  end;
end;

procedure TExecutionLifecycle.RequestCancel;
begin
  if FRunning then
    TInterlocked.Exchange(FCancelRequested, 1);
end;

function TExecutionLifecycle.IsCancellationRequested: Boolean;
begin
  Result := TInterlocked.CompareExchange(FCancelRequested, 0, 0) <> 0;
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
