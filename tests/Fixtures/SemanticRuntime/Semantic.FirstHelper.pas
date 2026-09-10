unit Semantic.FirstHelper;
interface
type
  TFirstHelper = record helper for string
    function SelectedHelper: string;
  end;
implementation
function TFirstHelper.SelectedHelper: string;
begin
  Result := 'First:' + Self;
end;
end.
