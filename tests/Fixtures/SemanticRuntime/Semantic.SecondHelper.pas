unit Semantic.SecondHelper;
interface
type
  TSecondHelper = record helper for string
    function SelectedHelper: string;
  end;
implementation
function TSecondHelper.SelectedHelper: string;
begin
  Result := 'Second:' + Self;
end;
end.
