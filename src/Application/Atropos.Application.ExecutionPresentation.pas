unit Atropos.Application.ExecutionPresentation;

interface

uses
  Atropos.Application.ExecutionLifecycle;

type
  TExecutionViewState = record
    ControlsEnabled: Boolean;
    CancelEnabled: Boolean;
    CancellationPending: Boolean;
    ProgressMaximum: Integer;
    ProgressPosition: Integer;
  end;

  TExecutionPresentation = class
  private
    FLifecycle: TExecutionLifecycle;
    FState: TExecutionViewState;
  public
    constructor Create;
    destructor Destroy; override;
    function TryBegin: Boolean;
    procedure RequestCancellation;
    procedure Complete;
    procedure UpdateProgress(AMaximum, APosition: Integer);
    function IsCancellationRequested: Boolean;
    function CanClose: Boolean;
    property State: TExecutionViewState read FState;
  end;

implementation

constructor TExecutionPresentation.Create;
begin
  inherited;
  FLifecycle := TExecutionLifecycle.Create;
  Complete;
end;

destructor TExecutionPresentation.Destroy;
begin
  FLifecycle.Free;
  inherited;
end;

function TExecutionPresentation.TryBegin: Boolean;
begin
  Result := FLifecycle.TryBegin;
  if not Result then
    Exit;
  FState.ControlsEnabled := False;
  FState.CancelEnabled := True;
  FState.CancellationPending := False;
  FState.ProgressMaximum := 0;
  FState.ProgressPosition := 0;
end;

procedure TExecutionPresentation.RequestCancellation;
begin
  FLifecycle.RequestCancel;
  if not FLifecycle.IsCancellationRequested then
    Exit;
  FState.CancelEnabled := False;
  FState.CancellationPending := True;
end;

procedure TExecutionPresentation.Complete;
begin
  FLifecycle.Complete;
  FState.ControlsEnabled := True;
  FState.CancelEnabled := False;
  FState.CancellationPending := False;
end;

procedure TExecutionPresentation.UpdateProgress(AMaximum, APosition: Integer);
begin
  FState.ProgressMaximum := AMaximum;
  FState.ProgressPosition := APosition;
end;

function TExecutionPresentation.IsCancellationRequested: Boolean;
begin
  Result := FLifecycle.IsCancellationRequested;
end;

function TExecutionPresentation.CanClose: Boolean;
begin
  Result := FLifecycle.CanClose;
end;

end.
