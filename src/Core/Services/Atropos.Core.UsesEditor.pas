unit Atropos.Core.UsesEditor;

interface

uses Atropos.Core.Analysis, Atropos.Core.UsesSyntax;

type
  TUsesEditor = class
  private
    FSource: string;
    procedure Replace(AStart, AEnd: Integer; const AText: string);
    function InsertInto(ADocument: TUsesSource; const AName, AText: string;
      ASection: TUsesSection): Boolean;
  public
    constructor Create(const ASource: string);
    function Remove(const AName: string; ASection: TUsesSection): Boolean;
    function Add(const AName, AText: string; ASection: TUsesSection): Boolean;
    function Move(const AName: string; AFromSection: TUsesSection = usInterface): Boolean;
    property Source: string read FSource;
  end;

implementation

uses System.SysUtils;

constructor TUsesEditor.Create(const ASource: string);
begin
  inherited Create;
  FSource := ASource;
end;

procedure TUsesEditor.Replace(AStart, AEnd: Integer; const AText: string);
begin
  Delete(FSource, AStart, AEnd - AStart);
  Insert(AText, FSource, AStart);
end;

function TUsesEditor.Remove(const AName: string; ASection: TUsesSection): Boolean;
var LDocument: TUsesSource; LClause: TUsesClause; LIndex, LStart, LEnd: Integer;
begin
  Result := False;
  LDocument := TUsesSource.Create(FSource);
  try
    if not LDocument.Find(AName, ASection, LClause, LIndex) then
      Exit;
    if not LClause.Complete or not LClause.Condition.IsEmpty or
      not LClause.Entries[LIndex].Condition.IsEmpty then
      Exit;
    LStart := LClause.Keyword;
    LEnd := LClause.Terminator + 1;
    if LClause.Entries.Count > 1 then
    begin
      LStart := LClause.Entries[LIndex].StartOffset;
      LEnd := LClause.Entries[LIndex].EndOffset;
      if LIndex < LClause.Entries.Count - 1 then
      begin
        if not LClause.Entries[LIndex + 1].Condition.IsEmpty then
          Exit;
        LEnd := LClause.Entries[LIndex + 1].StartOffset;
      end;
      if LIndex = LClause.Entries.Count - 1 then
      begin
        if not LClause.Entries[LIndex - 1].Condition.IsEmpty then
          Exit;
        LStart := LClause.Entries[LIndex - 1].Separator;
      end;
    end;
    if LDocument.HasDirectivesIn(LStart, LEnd) then
      Exit;
    Replace(LStart, LEnd, LDocument.Comments(LStart, LEnd));
    Result := True;
  finally
    LDocument.Free;
  end;
end;

function TUsesEditor.InsertInto(ADocument: TUsesSource; const AName, AText: string;
  ASection: TUsesSection): Boolean;
var LClause, LExisting: TUsesClause; LIndex, LCount: Integer; LBreak: string;
  LEntry: TUsesOccurrence;
begin
  Result := False;
  if ADocument.SectionEnd[ASection] = 0 then
    Exit;
  LCount := 0;
  for LClause in ADocument.Clauses do
    if LClause.Section = ASection then
      Inc(LCount);
  if LCount > 1 then
    Exit;
  LClause := ADocument.SectionClause(ASection);
  if ADocument.Find(AName, ASection, LExisting, LIndex) then
    Exit(LExisting.Complete and LExisting.Condition.IsEmpty and not LExisting.HasDirectives);
  LBreak := ADocument.LineBreak;
  if not Assigned(LClause) then
  begin
    if ADocument.HasHeaderInclude(ASection) then
      Exit;
    Insert(LBreak + 'uses' + LBreak + '  ' + AText + ';', FSource, ADocument.SectionEnd[ASection]);
    Exit(True);
  end;
  if not LClause.Complete then
    Exit;
  if LClause.HasDirectives then
    Exit;
  for LEntry in LClause.Entries do
    if SameText(LEntry.Name, AName) then
      Exit;
  if LClause.Condition.IsEmpty then
  begin
    Insert(' ' + AText + ',', FSource, LClause.Keyword + 4);
    Exit(True);
  end;
  if (LClause.GuardStart = 0) or (LClause.GuardEnd = 0) or LClause.HasDirectives then
    Exit;
  // Lift only a whole single guarded clause; its condition and entries remain intact.
  Insert(';', FSource, LClause.GuardEnd);
  Delete(FSource, LClause.Terminator, 1);
  Replace(LClause.Keyword, LClause.Keyword + 4, ',');
  Insert('uses ' + AText + LBreak, FSource, LClause.GuardStart);
  Result := True;
end;

function TUsesEditor.Add(const AName, AText: string; ASection: TUsesSection): Boolean;
var LDocument: TUsesSource;
begin
  LDocument := TUsesSource.Create(FSource);
  try
    Result := InsertInto(LDocument, AName, AText, ASection);
  finally
    LDocument.Free;
  end;
end;

function TUsesEditor.Move(const AName: string; AFromSection: TUsesSection): Boolean;
var LDocument: TUsesSource; LClause, LDestination: TUsesClause; LIndex, LOther: Integer;
  LEntry: TUsesOccurrence; LText, LOriginal, LOtherText: string;
  LTarget: TUsesSection;
begin
  Result := False;
  LTarget := usImplementation;
  if AFromSection = usImplementation then
    LTarget := usInterface;
  LOriginal := FSource;
  LDocument := TUsesSource.Create(FSource);
  try
    if not LDocument.Find(AName, AFromSection, LClause, LIndex) then
      Exit;
    if not LClause.Complete or LClause.HasDirectives or not LClause.Condition.IsEmpty then
      Exit;
    LEntry := LClause.Entries[LIndex];
    // Comments interleaved with an entry have no proven ownership for relocation.
    if not LDocument.Comments(LEntry.StartOffset, LEntry.EndOffset).IsEmpty then
      Exit;
    LText := Copy(FSource, LEntry.StartOffset, LEntry.EndOffset - LEntry.StartOffset);
    if LDocument.Find(AName, LTarget, LDestination, LOther) then
    begin
      LEntry := LDestination.Entries[LOther];
      LOtherText := Copy(FSource, LEntry.StartOffset, LEntry.EndOffset - LEntry.StartOffset);
      if not SameText(LText.Trim, LOtherText.Trim) then
        Exit;
    end;
  finally
    LDocument.Free;
  end;
  if not Add(AName, LText, LTarget) then
    Exit;
  Result := Remove(AName, AFromSection);
  if not Result then
    FSource := LOriginal;
end;

end.
