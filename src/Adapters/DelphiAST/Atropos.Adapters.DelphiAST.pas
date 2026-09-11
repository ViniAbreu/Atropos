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
    IUnitSymbolFacts, IUnitImplicitEffects, IUnitExportFacts)
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
    function GetExportFacts: TArray<TExportedSymbol>;
    function HasInitializationSection: Boolean;
    function GetSourceDependencies: TArray<TSourceDependency>;
    function GetIncompleteAnalysisReasons: TArray<string>;
    function GetPreservedImportNames: TArray<string>;
    function GetProjectImports: TArray<TUnitSourceMapping>;
    function GetLifecycleSections: TArray<TLifecycleSection>;
    function GetHelperDeclarations: TArray<THelperDeclaration>;
    function GetMemberReferences: TArray<TMemberReference>;
    function GetSymbolFacts: TUnitSymbolFacts;
    function GetImplicitEffects: TArray<TImplicitEffect>;
  end;

  TDelphiASTAdapter = class(TInterfacedObject, IASTParser, IAnalysisSnapshot,
    IProjectSnapshotInputs)
  private
    FIncludePaths: TArray<string>;
    FSnapshot: TSourceSnapshot;
    FParsedTrees: TDictionary<string, IUnitSyntaxTree>;
    FExplicitContext: Boolean;
    FDefines, FContextReasons: TArray<string>;
    FCompilerVersion: string;
    FOptions: TArray<TCompilerOption>;
    FNumbers: TArray<TCompilerOption>;
    function CreateSourceStream(const AFilePath: string;
      out AConstraints: TArray<string>; out AHash: string): TStringStream;
    function SyntaxKey(const AFilePath, AHash: string;
      const ADependencies: TArray<TSourceDependency>): string;
    function BuildSyntax(ABuilder: TPasSyntaxTreeBuilder; AStream: TStream;
      const AFilePath: string): TSyntaxNode;
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

uses Atropos.Core.Profiling, Atropos.Adapters.ExportFacts, Atropos.Adapters.ImplicitEffects, Atropos.Core.LocalBinding, Atropos.Adapters.SymbolFacts,
  Atropos.Adapters.MemberReferences, Atropos.Adapters.HelperFacts, Atropos.Adapters.SyntaxBuilder, Atropos.Adapters.SyntaxFacts, Atropos.Adapters.DelphiSource, Atropos.Adapters.SourceIncludes,
  Atropos.Adapters.ContextSyntaxBuilder,
  Atropos.Adapters.ConditionalSource,
  Atropos.Adapters.ConditionalImports,
  DelphiAST.SimpleParserEx, SimpleParser.Lexer, SimpleParser.Lexer.Types;

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
  FCompilerVersion := ASymbols.CompilerVersion;
  FOptions := ASymbols.DefaultSwitches + AContext.Options;
  FNumbers := Copy(ASymbols.NumericValues);
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
  FParsedTrees.Free;
  FSnapshot.Free;
  inherited;
end;

procedure TDelphiASTAdapter.BeginAnalysis;
begin
  if not Assigned(FParsedTrees) then
    FParsedTrees := TDictionary<string, IUnitSyntaxTree>.Create;
  FParsedTrees.Clear;
  FSnapshot.BeginAnalysis;
end;

procedure TDelphiASTAdapter.ValidateAnalysis;
begin
  FSnapshot.ValidateAnalysis;
end;

function TDelphiASTAdapter.CreateSourceStream(const AFilePath: string;
  out AConstraints: TArray<string>; out AHash: string): TStringStream;
var
  LSource: TDelphiSourceContent;
  LScanner: TConditionalImportScanner;
begin
  AConstraints := [];
  LSource := TDelphiSourceReader.Read(AFilePath);
  AHash := LSource.ContentHash;
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

function TDelphiASTAdapter.SyntaxKey(const AFilePath, AHash: string;
  const ADependencies: TArray<TSourceDependency>): string;
var LDependency: TSourceDependency;
begin
  Result := AFilePath + #0 + AHash;
  for LDependency in ADependencies do
    Result := Result + #0 + LDependency.ParentPath + #0 +
      LDependency.FilePath + #0 + LDependency.ContentHash;
end;

function TDelphiASTAdapter.BuildSyntax(ABuilder: TPasSyntaxTreeBuilder;
  AStream: TStream; const AFilePath: string): TSyntaxNode;
var LScope: IInterface;
begin
  LScope := TExecutionProfile.Measure('syntax-building', AFilePath);
  Result := ABuilder.Run(AStream);
end;

function TDelphiASTAdapter.ParseFile(const AFilePath: string): IUnitSyntaxTree;
var LProfileScope: IInterface;
  LBuilder: TPasSyntaxTreeBuilder;
  LRoot: TSyntaxNode;
  LSourceStream: TStringStream;
  LIncludes: TSourceIncludeResolver;
  LIncludeHandler: IIncludeHandler;
  LDefine: string;
  LReasons: TArray<string>;
  LConstraints: TArray<string>;
  LPrepared: TConditionalSource;
  LText, LVersion, LHash, LKey: string;
  LLexer: TmwPasLex;
begin
  LProfileScope := TExecutionProfile.Measure('parsing', AFilePath);
  if not FileExists(AFilePath) then
    raise EASTParserException.CreateFmt('File not found: %s', [AFilePath]);

  try
    LSourceStream := CreateSourceStream(AFilePath, LConstraints, LHash);
    try
      LBuilder := nil;
      if FExplicitContext then
        LBuilder := TContextSyntaxBuilder.Create;
      if not Assigned(LBuilder) then
        LBuilder := TAtroposSyntaxBuilder.Create;
      try
        LIncludes := TSourceIncludeResolver.Create(AFilePath, FIncludePaths, FSnapshot);
        if not FExplicitContext then
          LBuilder.InitDefinesDefinedByCompiler;
        if FExplicitContext then
          for LDefine in FDefines do
            LBuilder.AddDefine(LDefine);
        LVersion := FCompilerVersion;
        if not FExplicitContext then
          LVersion := FloatToStr(CompilerVersion, TFormatSettings.Invariant);
        LLexer := LBuilder.Lexer.Lexer;
        LPrepared := TConditionalSource.Create(LIncludes,
          function(AName: string): Boolean
          begin Result := LLexer.IsDefined(AName) end, LVersion, FOptions, FNumbers);
        LIncludeHandler := LPrepared;
        LBuilder.IncludeHandler := LIncludeHandler;
        LText := LPrepared.Prepare(LSourceStream.DataString, AFilePath);
        LKey := SyntaxKey(AFilePath, LHash, LPrepared.GetDependencies);
        if Assigned(FParsedTrees) then
          if FParsedTrees.TryGetValue(LKey, Result) then
            Exit;
        LSourceStream.Size := 0;
        LSourceStream.WriteString(LText);
        LSourceStream.Position := 0;
        LRoot := BuildSyntax(LBuilder, LSourceStream, AFilePath);
        if LRoot = nil then
          raise EASTParserException.Create('Parser returned nil tree.');

        LReasons := Copy(FContextReasons);
        if FExplicitContext then
          LReasons := LReasons + TContextSyntaxBuilder(LBuilder).IncompleteReasons;
        Result := TDelphiASTSyntaxTree.Create(AFilePath, LRoot,
          LPrepared.GetDependencies, LReasons, LConstraints);
        if Assigned(FParsedTrees) then
          FParsedTrees.AddOrSetValue(LKey, Result);
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
var LProfileScope: IInterface;
begin
  LProfileScope := TExecutionProfile.Measure('extraction', FFileName);
  Result := Copy(FIncompleteReasons);
  if HasIncludedUses(FRoot, False) then
    Result := Result + ['Uses entries originate in an include; editing their source provenance is not supported yet.'];
end;

function TDelphiASTSyntaxTree.GetUnitName: string;
begin
  Result := FUnitName;
end;

function TDelphiASTSyntaxTree.GetProjectImports: TArray<TUnitSourceMapping>;
var LProfileScope: IInterface;
begin
  LProfileScope := TExecutionProfile.Measure('extraction', FFileName);
  Result := TDelphiSyntaxFacts.ProjectImports(FRoot);
end;

function TDelphiASTSyntaxTree.GetHelperDeclarations: TArray<THelperDeclaration>;
var LProfileScope: IInterface; LExtractor: THelperFactExtractor;
begin
  LProfileScope := TExecutionProfile.Measure('extraction', FFileName);
  LExtractor := THelperFactExtractor.Create(FFileName);
  try
    Result := LExtractor.Extract(FRoot);
  finally
    LExtractor.Free;
  end;
end;

function TDelphiASTSyntaxTree.GetMemberReferences: TArray<TMemberReference>;
var LProfileScope: IInterface; LExtractor: TMemberReferenceExtractor;
begin
  LProfileScope := TExecutionProfile.Measure('extraction', FFileName);
  LExtractor := TMemberReferenceExtractor.Create;
  try
    Result := LExtractor.Extract(FRoot);
  finally
    LExtractor.Free;
  end;
end;

function TDelphiASTSyntaxTree.GetLifecycleSections: TArray<TLifecycleSection>;
var LProfileScope: IInterface;
begin
  LProfileScope := TExecutionProfile.Measure('extraction', FFileName);
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

function TDelphiASTSyntaxTree.GetUsesList(ANodeType: TSyntaxNodeType): TArray<string>;
var LProfileScope: IInterface;
  LNode: TSyntaxNode;
  LList: TList<string>;
begin
  LProfileScope := TExecutionProfile.Measure('extraction', FFileName);
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
var LProfileScope: IInterface; LExtractor: TSymbolFactExtractor;
begin
  LProfileScope := TExecutionProfile.Measure('extraction', FFileName);
  LExtractor := TSymbolFactExtractor.Create(FFileName);
  try
    Result := LExtractor.Extract(FRoot);
  finally
    LExtractor.Free;
  end;
end;

function TDelphiASTSyntaxTree.GetReferencedIdentifiers(AInterface: Boolean): TArray<string>;
var LProfileScope: IInterface; LBinding: TLocalSymbolBinding;
begin
  LProfileScope := TExecutionProfile.Measure('extraction', FFileName);
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

function TDelphiASTSyntaxTree.GetExportFacts: TArray<TExportedSymbol>;
var LProfileScope: IInterface; LExtractor: TExportFactExtractor;
begin
  LProfileScope := TExecutionProfile.Measure('extraction', FFileName);
  LExtractor := TExportFactExtractor.Create;
  try
    Result := LExtractor.Extract(FRoot);
  finally
    LExtractor.Free;
  end;
end;

function TDelphiASTSyntaxTree.GetExportedIdentifiers: TArray<string>;
var LProfileScope: IInterface; LHelper: THelperDeclaration; LFact: TExportedSymbol; LList: TList<string>;
begin
  LProfileScope := TExecutionProfile.Measure('extraction', FFileName);
  LList := TList<string>.Create;
  try
    for LFact in GetExportFacts do
      if not LList.Contains(LFact.Name) then
        LList.Add(LFact.Name);
    for LHelper in GetHelperDeclarations do
      if LHelper.Visibility <> 'private' then
        LList.Add('!HELPER:' + LHelper.MemberName + ':' + LHelper.ReceiverType);
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;
function TDelphiASTSyntaxTree.HasInitializationSection: Boolean;
var LProfileScope: IInterface; LEffect: TImplicitEffect;
begin
  LProfileScope := TExecutionProfile.Measure('extraction', FFileName);
  Result := Length(GetLifecycleSections) > 0;
  if Result then
    Exit;
  for LEffect in GetImplicitEffects do
    if LEffect.Definite then
      Exit(True);
end;

function TDelphiASTSyntaxTree.GetImplicitEffects: TArray<TImplicitEffect>;
var LProfileScope: IInterface; LExtractor: TImplicitEffectExtractor;
begin
  LProfileScope := TExecutionProfile.Measure('extraction', FFileName);
  LExtractor := TImplicitEffectExtractor.Create(FFileName);
  try
    Result := LExtractor.Extract(FRoot);
  finally
    LExtractor.Free;
  end;
end;

end.
