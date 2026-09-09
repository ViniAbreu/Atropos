unit Atropos.Adapters.ExecutionThread;

interface
uses System.Classes;

type
  TSynchronizedExecutionThread = class(TThread)
  private
    FComplete: TThreadMethod;
    FWork: TThreadProcedure;
  protected
    procedure Execute; override;
  public
    constructor Create(const AWork: TThreadProcedure;
      AComplete: TThreadMethod; AFreeOnTerminate: Boolean = True);
  end;

implementation

constructor TSynchronizedExecutionThread.Create(const AWork: TThreadProcedure;
  AComplete: TThreadMethod; AFreeOnTerminate: Boolean);
begin
  inherited Create(True);
  FWork := AWork;
  FComplete := AComplete;
  FreeOnTerminate := AFreeOnTerminate;
end;

procedure TSynchronizedExecutionThread.Execute;
begin
  try
    FWork();
  finally
    Synchronize(FComplete);
  end;
end;

end.
