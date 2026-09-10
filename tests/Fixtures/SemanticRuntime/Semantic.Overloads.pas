unit Semantic.Overloads;
interface
function Pick(Value: Integer): string; overload;
function Pick(const Value: string): string; overload;
implementation
function Pick(Value: Integer): string;
begin
  Result := 'Integer';
end;
function Pick(const Value: string): string;
begin
  Result := 'String';
end;
end.
