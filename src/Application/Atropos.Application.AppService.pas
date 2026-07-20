unit Atropos.Application.AppService;

interface
uses
  Atropos.Core.Ports, Atropos.Core.Config, System.IOUtils;

type
  TProgressEvent = reference to procedure(AMax, APosition: Integer);
  TLogEvent = reference to procedure(const AMsg: string);

  TProjectCleanerAppService = class
  private
    FProjectParser: IProjectParser;
    FASTParser: IASTParser;
    FFileService: IFileService;
    FReportGen: IReportGenerator;
    FDelphiEnvironment: IDelphiEnvironmentService;
    FResolver: IExternalUnitResolver;
    FConfig: TToolConfig;
    
    FOnProgress: TProgressEvent;
    FOnLog: TLogEvent;

    procedure Log(const AMsg: string);
    procedure Progress(AMax, APosition: Integer);
    function ResolvePath(const ABasePath, ARelativePath: string): string;
  public
    constructor Create(
      const AProjectParser: IProjectParser;
      const AASTParser: IASTParser;
      const AFileService: IFileService;
      const AReportGen: IReportGenerator;
      const ADelphiEnvironment: IDelphiEnvironmentService;
      const AResolver: IExternalUnitResolver;
      const AConfig: TToolConfig);
      
    property OnProgress: TProgressEvent read FOnProgress write FOnProgress;
    property OnLog: TLogEvent read FOnLog write FOnLog;

    procedure Execute(const ADprojPath: string);
  end;

implementation
uses
  Atropos.Core.Domain, Atropos.Core.Modifier, Atropos.Adapters.Logger, System.SysUtils;

constructor TProjectCleanerAppService.Create(
  const AProjectParser: IProjectParser;
  const AASTParser: IASTParser;
  const AFileService: IFileService;
  const AReportGen: IReportGenerator;
  const ADelphiEnvironment: IDelphiEnvironmentService;
  const AResolver: IExternalUnitResolver;
  const AConfig: TToolConfig);
begin
  FProjectParser := AProjectParser;
  FASTParser := AASTParser;
  FFileService := AFileService;
  FReportGen := AReportGen;
  FDelphiEnvironment := ADelphiEnvironment;
  FResolver := AResolver;
  FConfig := AConfig;
end;

procedure TProjectCleanerAppService.Log(const AMsg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(AMsg);
end;

procedure TProjectCleanerAppService.Progress(AMax, APosition: Integer);
begin
  if Assigned(FOnProgress) then
    FOnProgress(AMax, APosition);
end;

function TProjectCleanerAppService.ResolvePath(const ABasePath, ARelativePath: string): string;
begin
  if TPath.IsRelativePath(ARelativePath) then
    Result := TPath.GetFullPath(TPath.Combine(ABasePath, ARelativePath))
  else
    Result := ARelativePath;
end;

procedure TProjectCleanerAppService.Execute(const ADprojPath: string);
var
  LContext: TProjectContext;
  LSearchPaths: TArray<string>;
  LDelphiPath: string;
  LAnalyzer: TAnalyzeUnitUses;
  LModifier: TApplyUsesChanges;
  LLogger: ILogger;
  LResult: TUnitAnalysisResult;
  LSyntaxTree: IUnitSyntaxTree;
  LUnits: TArray<string>;
  LUnit, LUnitPath, LFullPath, LBasePath: string;
  i: Integer;
begin
  LFullPath := TPath.GetFullPath(ADprojPath);
  Log('Analyzing project: ' + LFullPath);
  Log('Loading dependencies... Please wait.');

  LBasePath := TPath.GetDirectoryName(LFullPath);
  
  LDelphiPath := FDelphiEnvironment.ResolveDelphiPath(LFullPath);
  if LDelphiPath = '' then
    Log('WARNING: Delphi environment not found. Standard RTL/VCL units will not be resolved and will be ignored.');

  LSearchPaths := FProjectParser.GetSearchPaths(LFullPath);
  LSearchPaths := LSearchPaths + [LBasePath];
  
  FResolver.Initialize(LSearchPaths, LDelphiPath, LBasePath);
  
  if FConfig.EnableDebug then
    LLogger := TAppLogger.Create(
      procedure(const AMsg: string)
      begin
        Self.Log(AMsg);
      end)
  else
    LLogger := nil;

  LContext := TProjectContext.Create(FResolver, LLogger);
  LAnalyzer := TAnalyzeUnitUses.Create(LLogger);
  LModifier := TApplyUsesChanges.Create(FFileService, FConfig);
  try
    LUnits := FProjectParser.GetProjectUnits(ADprojPath);
    Progress(Length(LUnits), 0);
    
    if Length(LUnits) = 0 then
    begin
      Log('No units found in project.');
      Exit;
    end;

    Log(Format('Found %d units to process.', [Length(LUnits)]));
    
    for i := 0 to High(LUnits) do
    begin
      LUnit := LUnits[i];
      LUnitPath := ResolvePath(LBasePath, LUnit);
      
      if not TFile.Exists(LUnitPath) then
      begin
        Log('Warning: File not found -> ' + LUnitPath);
        Progress(Length(LUnits), i + 1);
        Continue;
      end;
      
      try
        if Assigned(LLogger) then LLogger.Log('DEBUG: Parsing AST for ' + ExtractFileName(LUnitPath));
        LSyntaxTree := FASTParser.ParseFile(LUnitPath);
        
        if Assigned(LLogger) then LLogger.Log('DEBUG: Analyzing dependencies for ' + ExtractFileName(LUnitPath));
        LResult := LAnalyzer.Execute(LSyntaxTree, LContext);
        
        if (FConfig.RemoveUnused and (Length(LResult.UnusedUnits) > 0)) or
          (FConfig.MoveToImplementation and (Length(LResult.UnitsToMoveToImpl) > 0)) then
        begin
          LModifier.Execute(LUnitPath, LResult);
          FReportGen.AddUnitProcessed(LUnitPath, LResult.UnusedUnits, LResult.UnitsToMoveToImpl);
          Log('Cleaned: ' + ExtractFileName(LUnitPath));
        end;
      except
        on E: Exception do
          Log('Error processing ' + ExtractFileName(LUnitPath) + ': ' + E.Message);
      end;
      
      Progress(Length(LUnits), i + 1);
    end;
    
    Log('');
    Log(FReportGen.GetReportContent);
    
  finally
    LAnalyzer.Free;
    LContext.Free;
    LModifier.Free;
  end;
end;

end.

