unit Atropos.Core.Profiling;

interface

uses System.SysUtils, System.Generics.Collections;

type
  TProfileSample = record
    Phase, Subject: string;
    Calls, InclusiveTicks, ExclusiveTicks: Int64;
  end;

  TExecutionProfile = class;
  TProfileScope = class(TInterfacedObject)
  private
    FOwner: TExecutionProfile;
    FParent: TProfileScope;
    FIndex: Integer;
    FStart, FChildren: Int64;
  public
    constructor Create(AOwner: TExecutionProfile; AIndex: Integer);
    destructor Destroy; override;
  end;

  TExecutionProfile = class
  private
    FClock: TFunc<Int64>;
    FCurrent: TProfileScope;
    FIndexes: TDictionary<string, Integer>;
    FSamples: TList<TProfileSample>;
    function OpenScope(const APhase, ASubject: string): IInterface;
    procedure CloseScope(AScope: TProfileScope);
  public
    constructor Create(const AClock: TFunc<Int64> = nil);
    destructor Destroy; override;
    procedure Activate;
    procedure Deactivate;
    function Samples: TArray<TProfileSample>;
    class function Measure(const APhase: string; const ASubject: string = ''): IInterface; static;
    class function Frequency: Int64; static;
  end;

implementation

uses System.Diagnostics, System.Classes;

threadvar ActiveProfile: TExecutionProfile;

constructor TExecutionProfile.Create(const AClock: TFunc<Int64>);
begin
  inherited Create;
  FClock := AClock;
  if not Assigned(FClock) then
    FClock := function: Int64 begin Result := TStopwatch.GetTimeStamp end;
  FIndexes := TDictionary<string, Integer>.Create;
  FSamples := TList<TProfileSample>.Create;
end;

destructor TExecutionProfile.Destroy;
begin
  Deactivate;
  FSamples.Free;
  FIndexes.Free;
  inherited;
end;

procedure TExecutionProfile.Activate;
begin
  if Assigned(ActiveProfile) then
    raise EInvalidOperation.Create('A profile is already active on this thread');
  ActiveProfile := Self;
end;

procedure TExecutionProfile.Deactivate;
begin
  if Assigned(FCurrent) then
    raise EInvalidOperation.Create('Profile scopes must finish before deactivation');
  if ActiveProfile = Self then
    ActiveProfile := nil;
end;

class function TExecutionProfile.Frequency: Int64;
begin
  Result := TStopwatch.Frequency;
end;

class function TExecutionProfile.Measure(const APhase, ASubject: string): IInterface;
begin
  Result := nil;
  if Assigned(ActiveProfile) then
    Result := ActiveProfile.OpenScope(APhase, ASubject);
end;

function TExecutionProfile.OpenScope(const APhase, ASubject: string): IInterface;
var LIndex: Integer; LKey: string; LSample: TProfileSample;
begin
  LKey := APhase + #0 + ASubject;
  if not FIndexes.TryGetValue(LKey, LIndex) then
  begin
    LSample := Default(TProfileSample);
    LSample.Phase := APhase;
    LSample.Subject := ASubject;
    LIndex := FSamples.Add(LSample);
    FIndexes.Add(LKey, LIndex);
  end;
  Result := TProfileScope.Create(Self, LIndex);
end;

function TExecutionProfile.Samples: TArray<TProfileSample>;
begin
  if Assigned(FCurrent) then
    raise EInvalidOperation.Create('Cannot read an unfinished profile');
  Result := FSamples.ToArray;
end;

constructor TProfileScope.Create(AOwner: TExecutionProfile; AIndex: Integer);
begin
  inherited Create;
  FOwner := AOwner;
  FIndex := AIndex;
  FParent := AOwner.FCurrent;
  AOwner.FCurrent := Self;
  FStart := AOwner.FClock();
end;

destructor TProfileScope.Destroy;
begin
  FOwner.CloseScope(Self);
  inherited;
end;

procedure TExecutionProfile.CloseScope(AScope: TProfileScope);
var LElapsed: Int64; LSample: TProfileSample;
begin
  LElapsed := FClock() - AScope.FStart;
  LSample := FSamples[AScope.FIndex];
  Inc(LSample.Calls);
  Inc(LSample.InclusiveTicks, LElapsed);
  Inc(LSample.ExclusiveTicks, LElapsed - AScope.FChildren);
  FSamples[AScope.FIndex] := LSample;
  FCurrent := AScope.FParent;
  if Assigned(FCurrent) then
    Inc(FCurrent.FChildren, LElapsed);
end;

end.
