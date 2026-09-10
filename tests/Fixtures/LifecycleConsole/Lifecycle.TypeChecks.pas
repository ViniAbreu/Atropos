unit Lifecycle.TypeChecks;
interface
uses Lifecycle.Generic, Lifecycle.Plain, Lifecycle.Attributes;
type
  TIntBox = TBox<Integer>;
  [TMarker] TTagged = class end;
procedure CheckTypes;
implementation
uses System.Rtti;
procedure CheckTypes;
var Context: TRttiContext; Attributes: TArray<TCustomAttribute>; Box: TIntBox;
begin
  Box.Value := 7;
  if Box.Value <> 7 then
    Halt(2);
  Context := TRttiContext.Create;
  try
    Attributes := Context.GetType(TypeInfo(TTagged)).GetAttributes;
    if Length(Attributes) <> 1 then
      Halt(3);
    if not (Attributes[0] is TMarkerAttribute) then
      Halt(4);
  finally
    Context.Free;
  end;
end;
end.
