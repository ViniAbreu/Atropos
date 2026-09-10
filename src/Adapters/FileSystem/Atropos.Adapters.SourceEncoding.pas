unit Atropos.Adapters.SourceEncoding;

interface

uses System.SysUtils;

type
  TSourceEncoding = class
  public
    class function Detect(const ABytes: TBytes): TEncoding; static;
    class function IsValidUTF8(const ABytes: TBytes): Boolean; static;
  end;

implementation

class function TSourceEncoding.Detect(const ABytes: TBytes): TEncoding;
var
  LDetectedEncoding: TEncoding;
begin
  LDetectedEncoding := nil;
  if TEncoding.GetBufferEncoding(ABytes, LDetectedEncoding) > 0 then
    Exit(LDetectedEncoding);

  Result := TEncoding.Default;
  if IsValidUTF8(ABytes) then
    Result := TEncoding.UTF8;
end;

class function TSourceEncoding.IsValidUTF8(const ABytes: TBytes): Boolean;
var
  LIndex: Integer;
  LContinuationCount: Integer;
  LContinuationIndex: Integer;
begin
  Result := False;
  LIndex := 0;
  while LIndex < Length(ABytes) do
  begin
    if ABytes[LIndex] <= $7F then
    begin
      Inc(LIndex);
      Continue;
    end;

    LContinuationCount := 0;
    if (ABytes[LIndex] >= $C2) and (ABytes[LIndex] <= $DF) then
      LContinuationCount := 1;
    if (ABytes[LIndex] >= $E0) and (ABytes[LIndex] <= $EF) then
      LContinuationCount := 2;
    if (ABytes[LIndex] >= $F0) and (ABytes[LIndex] <= $F4) then
      LContinuationCount := 3;
    if LContinuationCount = 0 then
      Exit;
    if LIndex + LContinuationCount >= Length(ABytes) then
      Exit;

    for LContinuationIndex := 1 to LContinuationCount do
      if (ABytes[LIndex + LContinuationIndex] < $80) or (ABytes[LIndex + LContinuationIndex] > $BF) then
        Exit;

    if (ABytes[LIndex] = $E0) and (ABytes[LIndex + 1] < $A0) then
      Exit;
    if (ABytes[LIndex] = $ED) and (ABytes[LIndex + 1] > $9F) then
      Exit;
    if (ABytes[LIndex] = $F0) and (ABytes[LIndex + 1] < $90) then
      Exit;
    if (ABytes[LIndex] = $F4) and (ABytes[LIndex + 1] > $8F) then
      Exit;

    Inc(LIndex, LContinuationCount + 1);
  end;
  Result := True;
end;

end.
