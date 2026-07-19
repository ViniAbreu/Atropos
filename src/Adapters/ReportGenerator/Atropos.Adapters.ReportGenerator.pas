unit Atropos.Adapters.ReportGenerator;

interface
uses
  System.Generics.Collections, Atropos.Core.Ports;

type
  TReportItem = record
    UnitName: string;
    RemovedUses: TArray<string>;
    MovedUses: TArray<string>;
  end;

  TReportGeneratorAdapter = class(TInterfacedObject, IReportGenerator)
  private
    FItems: TList<TReportItem>;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure AddUnitProcessed(const AUnitName: string; const ARemovedUses, AMovedUses: TArray<string>);
    function GetReportContent: string;
    
    property Items: TList<TReportItem> read FItems;
  end;

implementation
uses
  System.SysUtils;



constructor TReportGeneratorAdapter.Create;
begin
  FItems := TList<TReportItem>.Create;
end;

destructor TReportGeneratorAdapter.Destroy;
begin
  FItems.Free;
  inherited;
end;

procedure TReportGeneratorAdapter.AddUnitProcessed(const AUnitName: string; const ARemovedUses, AMovedUses: TArray<string>);
var
  LItem: TReportItem;
begin
  LItem.UnitName := AUnitName;
  LItem.RemovedUses := ARemovedUses;
  LItem.MovedUses := AMovedUses;
  FItems.Add(LItem);
end;

function TReportGeneratorAdapter.GetReportContent: string;
var
  LItem: TReportItem;
  LUses: string;
  LBuilder: TStringBuilder;
  LHasChanges: Boolean;
begin
  if FItems.Count = 0 then
    Exit('No files were processed.');

  LBuilder := TStringBuilder.Create;
  try
    LBuilder.AppendLine('Atropos - Processing Report');
    LBuilder.AppendLine('===============================');
    
    LHasChanges := False;
    
    for LItem in FItems do
    begin
      if (Length(LItem.RemovedUses) = 0) and (Length(LItem.MovedUses) = 0) then
        Continue;
        
      LHasChanges := True;
      LBuilder.AppendLine('');
      LBuilder.AppendLine('File: ' + LItem.UnitName);
      
      if Length(LItem.RemovedUses) > 0 then
      begin
        LBuilder.AppendLine('  Removed Uses:');
        for LUses in LItem.RemovedUses do
          LBuilder.AppendLine('    - ' + LUses);
      end;
      
      if Length(LItem.MovedUses) > 0 then
      begin
        LBuilder.AppendLine('  Moved to Implementation Uses:');
        for LUses in LItem.MovedUses do
          LBuilder.AppendLine('    - ' + LUses);
      end;
    end;
    
    if not LHasChanges then
      Result := 'All files are clean. No units were removed or moved.'
    else
      Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

end.


