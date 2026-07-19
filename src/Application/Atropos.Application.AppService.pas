unit Atropos.Application.AppService;

interface
uses
  Atropos.Core.Ports;

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
      const AResolver: IExternalUnitResolver);
      
    property OnProgress: TProgressEvent read FOnProgress write FOnProgress;
    property OnLog: TLogEvent read FOnLog write FOnLog;

    procedure Execute(const ADprojPath: string);
  end;

implementation
uses
  Atropos.Core.Domain, Atropos.Core.Modifier, System.SysUtils, System.IOUtils;



constructor TProjectCleanerAppService.Create(
  const AProjectParser: IProjectParser;
  const AASTParser: IASTParser;
  const AFileService: IFileService;
  const AReportGen: IReportGenerator;
  const ADelphiEnvironment: IDelphiEnvironmentService;
  const AResolver: IExternalUnitResolver);
begin
  FProjectParser := AProjectParser;
  FASTParser := AASTParser;
  FFileService := AFileService;
  FReportGen := AReportGen;
  FDelphiEnvironment := ADelphiEnvironment;
  FResolver := AResolver;
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
  
  LContext := TProjectContext.Create(FResolver);
  LAnalyzer := TAnalyzeUnitUses.Create;
  LModifier := TApplyUsesChanges.Create(FFileService);
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
        LSyntaxTree := FASTParser.ParseFile(LUnitPath);
        LResult := LAnalyzer.Execute(LSyntaxTree, LContext);
        
        if (Length(LResult.UnusedUnits) > 0) or (Length(LResult.UnitsToMoveToImpl) > 0) then
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

