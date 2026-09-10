unit Semantic.Fallback;
interface
function Pick(const Value: Variant): string; overload;
implementation
function Pick(const Value: Variant): string;
begin
  Result := 'Variant';
end;
end.
