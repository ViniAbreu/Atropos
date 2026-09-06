unit Fixture.Aliased;

interface

type
  TAliased = record
    class function Value: string; static;
  end;

implementation

class function TAliased.Value: string;
begin
  Result := 'representative console fixture';
end;

end.
