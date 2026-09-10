unit Atropos.Adapters.SyntaxFacts;

interface

uses Atropos.Core.Ports, Atropos.Core.Compilation, DelphiAST.Classes;

type
  TDelphiSyntaxFacts = class
  public
    class function ProjectImports(ARoot: TSyntaxNode): TArray<TUnitSourceMapping>; static;
    class function LifecycleSections(ARoot: TSyntaxNode;
      const ASourcePath: string): TArray<TLifecycleSection>; static;
  end;

implementation

uses System.SysUtils, System.Generics.Collections, DelphiAST.Consts;

class function TDelphiSyntaxFacts.ProjectImports(ARoot: TSyntaxNode): TArray<TUnitSourceMapping>;
var
  LUses, LChild: TSyntaxNode;
  LMapping: TUnitSourceMapping;
  LMappings: TList<TUnitSourceMapping>;
begin
  LMappings := TList<TUnitSourceMapping>.Create;
  try
    LUses := ARoot.FindNode(ntUses);
    if Assigned(LUses) then
      for LChild in LUses.ChildNodes do
      begin
        if LChild.Typ <> ntUnit then
          Continue;
        LMapping.UnitName := LChild.GetAttribute(anName);
        LMapping.FilePath := LChild.GetAttribute(anPath);
        LMappings.Add(LMapping);
      end;
    Result := LMappings.ToArray;
  finally
    LMappings.Free;
  end;
end;

class function TDelphiSyntaxFacts.LifecycleSections(ARoot: TSyntaxNode;
  const ASourcePath: string): TArray<TLifecycleSection>;
const
  CNodeTypes: array[TLifecyclePhase] of TSyntaxNodeType =
    (ntInitialization, ntFinalization, ntStatements);
var
  LNode: TSyntaxNode;
  LPhase: TLifecyclePhase;
  LSection: TLifecycleSection;
  LSections: TList<TLifecycleSection>;
begin
  Result := [];
  if not Assigned(ARoot) then
    Exit;
  if not Assigned(ARoot.FindNode(ntInterface)) then
    Exit;
  LSections := TList<TLifecycleSection>.Create;
  try
    for LPhase := Low(TLifecyclePhase) to High(TLifecyclePhase) do
    begin
      LNode := ARoot.FindNode(CNodeTypes[LPhase]);
      if not Assigned(LNode) then
        Continue;
      LSection.Phase := LPhase;
      LSection.SourcePath := LNode.FileName;
      if LSection.SourcePath.IsEmpty then
        LSection.SourcePath := ASourcePath;
      LSection.NormalizedLine := LNode.Line;
      LSection.NormalizedColumn := LNode.Col;
      LSections.Add(LSection);
    end;
    Result := LSections.ToArray;
  finally
    LSections.Free;
  end;
end;

end.
