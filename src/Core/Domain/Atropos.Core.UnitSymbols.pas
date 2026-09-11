unit Atropos.Core.UnitSymbols;
interface
uses System.Generics.Collections;
type
  TUnitExports = class
  public
    UnitName: string;
    ExportedIdentifiers: TList<string>;
    ExportedHelpers: TObjectDictionary<string, TList<string>>;
    HasInitialization: Boolean;
    Imports: TArray<string>;
    ImportsKnown: Boolean;
    IsNative: Boolean;
    constructor Create(const AUnitName: string; AHasInit: Boolean = False; AIsNative: Boolean = False);
    destructor Destroy; override;
  end;
implementation
constructor TUnitExports.Create(const AUnitName: string; AHasInit: Boolean = False; AIsNative: Boolean = False);
begin
  UnitName := AUnitName;
  HasInitialization := AHasInit;
  ImportsKnown := False;
  IsNative := AIsNative;
  ExportedIdentifiers := TList<string>.Create;
  ExportedHelpers := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
end;

destructor TUnitExports.Destroy;
begin
  ExportedHelpers.Free;
  ExportedIdentifiers.Free;
  inherited;
end;

end.
