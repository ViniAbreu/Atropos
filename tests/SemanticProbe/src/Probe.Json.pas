unit Probe.Json;

interface

uses System.JSON, System.SysUtils;

type
  TProbeJson = class
  public
    class function Text(Value: TJSONObject; const Key: string;
      const Default: string = ''): string; static;
    class function Flag(Value: TJSONObject; const Key: string;
      Default: Boolean = False): Boolean; static;
    class function Strings(Value: TJSONObject; const Key: string): TArray<string>; static;
    class procedure Put(Value: TJSONObject; const Key: string;
      const Items: TArray<string>); static;
  end;

implementation

class function TProbeJson.Text(Value: TJSONObject; const Key, Default: string): string;
var Item: TJSONValue;
begin
  Item := Value.GetValue(Key);
  if not Assigned(Item) then
    Exit(Default);
  Result := Item.Value;
end;

class function TProbeJson.Flag(Value: TJSONObject; const Key: string;
  Default: Boolean): Boolean;
begin
  Result := SameText(Text(Value, Key, BoolToStr(Default, True)), 'true');
end;

class function TProbeJson.Strings(Value: TJSONObject; const Key: string): TArray<string>;
var Items: TJSONArray; Index: Integer;
begin
  Result := [];
  Items := Value.GetValue(Key) as TJSONArray;
  if not Assigned(Items) then
    Exit;
  SetLength(Result, Items.Count);
  for Index := 0 to Items.Count - 1 do
    Result[Index] := Items.Items[Index].Value;
end;

class procedure TProbeJson.Put(Value: TJSONObject; const Key: string;
  const Items: TArray<string>);
var Values: TJSONArray; Item: string;
begin
  Values := TJSONArray.Create;
  for Item in Items do
    Values.Add(Item);
  Value.AddPair(Key, Values);
end;

end.
