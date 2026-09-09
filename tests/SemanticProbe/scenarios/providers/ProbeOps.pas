unit ProbeOps;
interface
type TNumber = record
  Value: Integer;
  class operator Add(const Left, Right: TNumber): TNumber;
end;
implementation
class operator TNumber.Add(const Left, Right: TNumber): TNumber;
begin Result.Value := Left.Value + Right.Value; end;
end.
