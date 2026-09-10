unit Atropos.Adapters.DelphiAST;

interface
uses
  System.SysUtils,
  System.Generics.Collections,
  Atropos.Core.Ports,
  Atropos.Core.Compilation,
  Atropos.Adapters.SourceSnapshot,
  DelphiAST.Classes,
  DelphiAST.Consts, DelphiAST,
  System.Classes;

type
  EASTParserException = class(Exception);

  TDelphiASTSyntaxTree = class(TInterfacedObject, IUnitSyntaxTree,
    IUnitSourceDependencies, IUnitAnalysisDiagnostics, IUnitImportConstraints,
    IProjectSourceImports, IUnitLifecycleFacts, IUnitHelperFacts, IUnitMemberReferences,
    IUnitSymbolFacts)
  private
    FFileName: string;
    FUnitName: string;
    FRoot: TSyntaxNode;
    FDependencies: TArray<TSourceDependency>;
    FIncompleteReasons: TArray<string>;
    FPreservedImports: TArray<string>;
    function HasIncludedUses(ANode: TSyntaxNode; AInsideUses: Boolean): Boolean;
    
    function GetUsesList(ANodeType: TSyntaxNodeType): TArray<string>;
    function GetReferencedIdentifiers(AInterface: Boolean): TArray<string>;
    
    procedure FindAllUses(ANode: TSyntaxNode; AList: TList<string>);
    
    function ExtractNodeName(ANode: TSyntaxNode): string;
    function CanExportNode(ANode: TSyntaxNode; AInsideTypeDecl, AInsideHelper: Boolean): Boolean;
    function IsHelperNode(ANode: TSyntaxNode): Boolean;
    
    procedure FindExportedIdentifiers(ANode: TSyntaxNode; AList: TList<string>; ATypeDeclDepth: Integer = 0; AInsideHelper: Boolean = False);
  public
    constructor Create(const AFileName: string; ARoot: TSyntaxNode;
      const ADependencies: TArray<TSourceDependency>;
      const AReasons: TArray<string> = nil;
      const AConstraints: TArray<string> = nil);
    destructor Destroy; override;
    
    function GetUnitName: string;
    function GetInterfaceUses: TArray<string>;
    function GetImplementationUses: TArray<string>;
    function GetIdentifiersUsedInInterface: TArray<string>;
    function GetIdentifiersUsedInImplementation: TArray<string>;
    function GetExportedIdentifiers: TArray<string>;
    function HasInitializationSection: Boolean;
    function GetSourceDependencies: TArray<TSourceDependency>;
    function GetIncompleteAnalysisReasons: TArray<string>;
    function GetPreservedImportNames: TArray<string>;
    function GetProjectImports: TArray<TUnitSourceMapping>;
    function GetLifecycleSections: TArray<TLifecycleSection>;
    function GetHelperDeclarations: TArray<THelperDeclaration>;
    function GetMemberReferences: TArray<TMemberReference>;
    function GetSymbolFacts: TUnitSymbolFacts;
  end;

  TDelphiASTAdapter = class(TInterfacedObject, IASTParser, IAnalysisSnapshot,
    IProjectSnapshotInputs)
  private
    FIncludePaths: TArray<string>;
    FSnapshot: TSourceSnapshot;
    FExplicitContext: Boolean;
    FDefines, FContextReasons: TArray<string>;
    function CreateSourceStream(const AFilePath: string;
      out AConstraints: TArray<string>): TStringStream;
  public
    constructor Create; overload;
    constructor Create(const AIncludePaths: TArray<string>); overload;
    constructor Create(const AContext: TProjectCompilationContext;
      const ASymbols: TCompilerSymbols); overload;
    destructor Destroy; override;
    procedure BeginAnalysis;
    procedure ValidateAnalysis;
    procedure RegisterProjectInputs(const AFiles: TArray<TSourceDependency>);
    function ParseFile(const AFilePath: string): IUnitSyntaxTree;
  end;

implementation

uses Atropos.Core.LocalBinding, Atropos.Adapters.SymbolFacts,
  Atropos.Adapters.MemberReferences, Atropos.Adapters.HelperFacts, Atropos.Adapters.SyntaxBuilder, Atropos.Adapters.SyntaxFacts, Atropos.Adapters.DelphiSource, Atropos.Adapters.SourceIncludes,
  Atropos.Adapters.ContextSyntaxBuilder,
  Atropos.Adapters.ConditionalImports,
  SimpleParser.Lexer.Types;

constructor TDelphiASTAdapter.Create;
begin
  inherited Create;
  FSnapshot := TSourceSnapshot.Create;
end;

constructor TDelphiASTAdapter.Create(const AIncludePaths: TArray<string>);
begin
  inherited Create;
  FSnapshot := TSourceSnapshot.Create;
  FIncludePaths := Copy(AIncludePaths);
end;

constructor TDelphiASTAdapter.Create(const AContext: TProjectCompilationContext;
  const ASymbols: TCompilerSymbols);
begin
  inherited Create;
  FSnapshot := TSourceSnapshot.Create;
  FExplicitContext := True;
  FIncludePaths := Copy(AContext.IncludePaths);
  FDefines := ASymbols.Defines + AContext.Defines;
  if Length(AContext.DeferredProperties) > 0 then
    FContextReasons := ['Build targets can change compiler settings: ' +
      string.Join(', ', AContext.DeferredProperties)];
end;

procedure TDelphiASTAdapter.RegisterProjectInputs(const AFiles: TArray<TSourceDependency>);
var LFile: TSourceDependency;
begin
  for LFile in AFiles do
    FSnapshot.RecordSource(LFile.FilePath, LFile.ContentHash);
end;

destructor TDelphiASTAdapter.Destroy;
begin
  FSnapshot.Free;
  inherited;
end;

procedure TDelphiASTAdapter.BeginAnalysis;
begin
  FSnapshot.BeginAnalysis;
end;

procedure TDelphiASTAdapter.ValidateAnalysis;
begin
  FSnapshot.ValidateAnalysis;
end;

function TDelphiASTAdapter.CreateSourceStream(const AFilePath: string;
  out AConstraints: TArray<string>): TStringStream;
var
  LSource: TDelphiSourceContent;
  LScanner: TConditionalImportScanner;
begin
  AConstraints := [];
  LSource := TDelphiSourceReader.Read(AFilePath);
  FSnapshot.RecordSource(AFilePath, LSource.ContentHash);
  if FExplicitContext then
  begin
    LScanner := TConditionalImportScanner.Create;
    try
      AConstraints := LScanner.Find(LSource.Text);
    finally
      LScanner.Free;
    end;
  end;
  Result := TStringStream.Create(LSource.Text, TEncoding.UTF8);
end;

function TDelphiASTAdapter.ParseFile(const AFilePath: string): IUnitSyntaxTree;
var
  LBuilder: TPasSyntaxTreeBuilder;
  LRoot: TSyntaxNode;
  LSourceStream: TStringStream;
  LIncludes: TSourceIncludeResolver;
  LIncludeHandler: IIncludeHandler;
  LDefine: string;
  LReasons: TArray<string>;
  LConstraints: TArray<string>;
begin
  if not FileExists(AFilePath) then
    raise EASTParserException.CreateFmt('File not found: %s', [AFilePath]);

  try
    LSourceStream := CreateSourceStream(AFilePath, LConstraints);
    try
      LBuilder := nil;
      if FExplicitContext then
        LBuilder := TContextSyntaxBuilder.Create;
      if not Assigned(LBuilder) then
        LBuilder := TAtroposSyntaxBuilder.Create;
      try
        LIncludes := TSourceIncludeResolver.Create(AFilePath, FIncludePaths, FSnapshot);
        LIncludeHandler := LIncludes;
        LBuilder.IncludeHandler := LIncludeHandler;
        if not FExplicitContext then
          LBuilder.InitDefinesDefinedByCompiler;
        if FExplicitContext then
          for LDefine in FDefines do
            LBuilder.AddDefine(LDefine);
        LRoot := LBuilder.Run(LSourceStream);
        if LRoot = nil then
          raise EASTParserException.Create('Parser returned nil tree.');

        LReasons := Copy(FContextReasons);
        if FExplicitContext then
          LReasons := LReasons + TContextSyntaxBuilder(LBuilder).IncompleteReasons;
        Result := TDelphiASTSyntaxTree.Create(AFilePath, LRoot,
          LIncludes.GetDependencies, LReasons, LConstraints);
      finally
        LBuilder.Free;
      end;
    finally
      LSourceStream.Free;
    end;
  except
    on E: Exception do
      raise EASTParserException.CreateFmt('Error parsing file "%s": %s', [AFilePath, E.Message]);
  end;
end;

constructor TDelphiASTSyntaxTree.Create(const AFileName: string; ARoot: TSyntaxNode;
  const ADependencies: TArray<TSourceDependency>; const AReasons: TArray<string>;
  const AConstraints: TArray<string>);
begin
  FFileName := AFileName;
  FRoot := ARoot;
  FDependencies := Copy(ADependencies);
  FIncompleteReasons := Copy(AReasons);
  FPreservedImports := Copy(AConstraints);
  FUnitName := ExtractFileName(AFileName);
  if Assigned(FRoot) and (FRoot.Typ = ntUnit) then
  begin
    if FRoot.HasAttribute(anName) then
      FUnitName := FRoot.GetAttribute(anName);
  end;
end;

destructor TDelphiASTSyntaxTree.Destroy;
begin
  FRoot.Free;
  inherited;
end;

function TDelphiASTSyntaxTree.GetSourceDependencies: TArray<TSourceDependency>;
begin
  Result := Copy(FDependencies);
end;

function TDelphiASTSyntaxTree.GetPreservedImportNames: TArray<string>;
begin
  Result := Copy(FPreservedImports);
end;

function TDelphiASTSyntaxTree.HasIncludedUses(ANode: TSyntaxNode;
  AInsideUses: Boolean): Boolean;
var
  LChild: TSyntaxNode;
begin
  Result := False;
  if not Assigned(ANode) then
    Exit;
  AInsideUses := AInsideUses or (ANode.Typ = ntUses);
  if AInsideUses and not ANode.FileName.IsEmpty then
    Exit(True);
  for LChild in ANode.ChildNodes do
  begin
    if HasIncludedUses(LChild, AInsideUses) then
      Exit(True);
  end;
end;

function TDelphiASTSyntaxTree.GetIncompleteAnalysisReasons: TArray<string>;
begin
  Result := Copy(FIncompleteReasons);
  if HasIncludedUses(FRoot, False) then
    Result := Result + ['Uses entries originate in an include; editing their source provenance is not supported yet.'];
end;

function TDelphiASTSyntaxTree.GetUnitName: string;
begin
  Result := FUnitName;
end;

function TDelphiASTSyntaxTree.GetProjectImports: TArray<TUnitSourceMapping>;
begin
  Result := TDelphiSyntaxFacts.ProjectImports(FRoot);
end;

function TDelphiASTSyntaxTree.GetHelperDeclarations: TArray<THelperDeclaration>;
var LExtractor: THelperFactExtractor;
begin
  LExtractor := THelperFactExtractor.Create(FFileName);
  try
    Result := LExtractor.Extract(FRoot);
  finally
    LExtractor.Free;
  end;
end;

function TDelphiASTSyntaxTree.GetMemberReferences: TArray<TMemberReference>;
var LExtractor: TMemberReferenceExtractor;
begin
  LExtractor := TMemberReferenceExtractor.Create;
  try
    Result := LExtractor.Extract(FRoot);
  finally
    LExtractor.Free;
  end;
end;

function TDelphiASTSyntaxTree.GetLifecycleSections: TArray<TLifecycleSection>;
begin
  Result := TDelphiSyntaxFacts.LifecycleSections(FRoot, FFileName);
end;
procedure TDelphiASTSyntaxTree.FindAllUses(ANode: TSyntaxNode; AList: TList<string>);
var
  LChild: TSyntaxNode;
  LUsesNode: TSyntaxNode;
  LUnitName: string;
begin
  if not Assigned(ANode) then Exit;
  
  LUsesNode := ANode.FindNode(ntUses);
  if Assigned(LUsesNode) then
  begin
    for LChild in LUsesNode.ChildNodes do
    begin
      if (LChild.Typ = ntUnit) and LChild.HasAttribute(anName) then
      begin
        LUnitName := LChild.GetAttribute(anName);
        if not LUnitName.ToLower.EndsWith('.dcu') then
          AList.Add(LUnitName);
      end;
    end;
  end;
end;

function TDelphiASTSyntaxTree.ExtractNodeName(ANode: TSyntaxNode): string;
var
  LChild: TSyntaxNode;
  i: Integer;
begin
  if not Assigned(ANode) then
  begin
    Result := EmptyStr;
    Exit;
  end;

  Result := ANode.GetAttribute(anName);
  if not Result.IsEmpty then
    Exit;

  if ANode is TValuedSyntaxNode then
  begin
    Result := TValuedSyntaxNode(ANode).Value;
    if not Result.IsEmpty then
      Exit;
  end;

  // Pass 1: ntName
  for i := 0 to Length(ANode.ChildNodes) - 1 do
  begin
    LChild := ANode.ChildNodes[i];
    if LChild.Typ = ntName then
    begin
      Result := ExtractNodeName(LChild);
      if not Result.IsEmpty then
        Exit;
    end;
  end;

  // Pass 2: Fallback to ntIdentifier
  for i := 0 to Length(ANode.ChildNodes) - 1 do
  begin
    LChild := ANode.ChildNodes[i];
    if LChild.Typ = ntIdentifier then
    begin
      Result := ExtractNodeName(LChild);
      if not Result.IsEmpty then
        Exit;
    end;
  end;
end;

function TDelphiASTSyntaxTree.CanExportNode(ANode: TSyntaxNode; AInsideTypeDecl, AInsideHelper: Boolean): Boolean;
begin
  Result := False;
  
  if AInsideTypeDecl then
  begin
    if ANode.Typ = ntElement then
      Exit(True);
      
    if (ANode.Typ = ntIdentifier) and Assigned(ANode.ParentNode) and 
       (ANode.ParentNode.Typ = ntType) and (ANode.ParentNode.GetAttribute(anName).Equals('enum')) then
      Exit(True);
      
    Exit;
  end;
  
  if ANode.Typ in [ntTypeDecl, ntVariable, ntConstant, ntMethod, ntResourceString] then
    Result := True;
end;

function TDelphiASTSyntaxTree.IsHelperNode(ANode: TSyntaxNode): Boolean;
begin
  Result := Assigned(ANode.FindNode(ntHelper));
  if not Result and (ANode.Typ = ntTypeDecl) then
    Result := Assigned(ANode.FindNode([ntType, ntHelper]));
end;

procedure TDelphiASTSyntaxTree.FindExportedIdentifiers(ANode: TSyntaxNode; AList: TList<string>; ATypeDeclDepth: Integer = 0; AInsideHelper: Boolean = False);
var
  LChild: TSyntaxNode;
  LTypeDeclDepth: Integer;
  LIsHelper: Boolean;
  LName: string;
  I: Integer;
begin
  if not Assigned(ANode) then
    Exit;
  
  if ANode.Typ = ntUses then
    Exit;
    
  if ANode.Typ = ntHelper then
    Exit;
    
  // Se encontrarmos um ntTypeDecl estando já dentro de um (Depth > 0), é um Nested Type!
  // Tipos aninhados (e seus enums) pertencem à classe, não ao escopo global.
  if (ATypeDeclDepth > 0) and (ANode.Typ = ntTypeDecl) then
    Exit;

  LName := ExtractNodeName(ANode);
  
  if not LName.IsEmpty and CanExportNode(ANode, ATypeDeclDepth > 0, AInsideHelper) then
    AList.Add(LName);
    
  // NADA dentro de um método (parâmetros, variáveis locais, except blocks) é exportado globalmente.
  // Devemos sair DEPOIS de extrair o nome do próprio método.
  if ANode.Typ = ntMethod then
    Exit;
    
  LTypeDeclDepth := ATypeDeclDepth;
  if ANode.Typ = ntTypeDecl then
    Inc(LTypeDeclDepth);
    
  LIsHelper := AInsideHelper or (ANode.Typ = ntHelper);
  
  if (ANode.Typ in [ntTypeDecl, ntType]) and not LIsHelper then
    LIsHelper := IsHelperNode(ANode);
  
  for I := 0 to Length(ANode.ChildNodes) - 1 do
  begin
    LChild := ANode.ChildNodes[I];
    FindExportedIdentifiers(LChild, AList, LTypeDeclDepth, LIsHelper);
  end;
end;

function TDelphiASTSyntaxTree.GetUsesList(ANodeType: TSyntaxNodeType): TArray<string>;
var
  LNode: TSyntaxNode;
  LList: TList<string>;
begin
  Result := [];
  if not Assigned(FRoot) then
    Exit;
  
  LNode := FRoot.FindNode(ANodeType);
  if Assigned(LNode) then
  begin
    LList := TList<string>.Create;
    try
      FindAllUses(LNode, LList);
      Result := LList.ToArray;
    finally
      LList.Free;
    end;
  end;
end;

function TDelphiASTSyntaxTree.GetSymbolFacts: TUnitSymbolFacts;
var LExtractor: TSymbolFactExtractor;
begin
  LExtractor := TSymbolFactExtractor.Create(FFileName);
  try
    Result := LExtractor.Extract(FRoot);
  finally
    LExtractor.Free;
  end;
end;

function TDelphiASTSyntaxTree.GetReferencedIdentifiers(AInterface: Boolean): TArray<string>;
var LBinding: TLocalSymbolBinding;
begin
  LBinding := TLocalSymbolBinding.Create(GetSymbolFacts);
  try
    Result := LBinding.Identifiers(AInterface);
  finally
    LBinding.Free;
  end;
end;
function TDelphiASTSyntaxTree.GetInterfaceUses: TArray<string>;
begin
  Result := GetUsesList(ntInterface);
end;

function TDelphiASTSyntaxTree.GetImplementationUses: TArray<string>;
begin
  Result := GetUsesList(ntImplementation);
end;

function TDelphiASTSyntaxTree.GetIdentifiersUsedInInterface: TArray<string>;
begin
  Result := GetReferencedIdentifiers(True);
end;

function TDelphiASTSyntaxTree.GetIdentifiersUsedInImplementation: TArray<string>;
begin
  Result := GetReferencedIdentifiers(False);
end;

function TDelphiASTSyntaxTree.GetExportedIdentifiers: TArray<string>;
var
  LHelper: THelperDeclaration;
  LNode: TSyntaxNode;
  LList: TList<string>;
begin
  Result := [];
  if not Assigned(FRoot) then
    Exit;
  
  LNode := FRoot.FindNode(ntInterface);
  if Assigned(LNode) then
  begin
    LList := TList<string>.Create;
    try
      FindExportedIdentifiers(LNode, LList);
      for LHelper in GetHelperDeclarations do
        if LHelper.Visibility <> 'private' then
          LList.Add('!HELPER:' + LHelper.MemberName + ':' + LHelper.ReceiverType);
      Result := LList.ToArray;
    finally
      LList.Free;
    end;
  end;
end;

function TDelphiASTSyntaxTree.HasInitializationSection: Boolean;
begin
  Result := Length(GetLifecycleSections) > 0;
end;

end.

