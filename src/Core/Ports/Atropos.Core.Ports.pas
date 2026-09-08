unit Atropos.Core.Ports;

interface

uses
  System.SysUtils;

type
  TCancellationCheck = reference to function: Boolean;

  TBuildTarget = record
  private
    class function IsValidPart(const AValue: string): Boolean; static;
  public
    Configuration: string;
    Platform: string;
    constructor Create(const AConfiguration, APlatform: string);
    function IsValid: Boolean;
    class function TryParse(const AValue: string;
      out ATarget: TBuildTarget): Boolean; static;
  end;

  TInlineHint = record
    HintType: string;
    FilePath: string;
    UnitNeeded: string;
  end;

  TBuildMetrics = record
    Hints: Integer;
    Warnings: Integer;
    CompileTimeMs: Int64;
    ExeSizeBytes: Int64;
    Success: Boolean;
    ErrorMessage: string;
    RemovedUnitsCount: Integer;
    MovedUnitsCount: Integer;
    DelphiVersion: string;
    ResolvedInlineHintsCount: Integer;
    InlineHints: TArray<TInlineHint>;
  end;

  ILogger = interface
    ['{884D2B60-70E7-4581-BC77-62F16298BB38}']
    procedure Log(const AMsg: string);
  end;

  IUnitSyntaxTree = interface
    ['{BFA9B996-339A-40C6-90B1-50793D99E416}']
    function GetUnitName: string;
    function GetInterfaceUses: TArray<string>;
    function GetImplementationUses: TArray<string>;
    function GetIdentifiersUsedInInterface: TArray<string>;
    function GetIdentifiersUsedInImplementation: TArray<string>;
    function GetExportedIdentifiers: TArray<string>;
    function HasInitializationSection: Boolean;
  end;
  
  IProjectParser = interface
    ['{EAC338C4-E143-41BE-8176-B8EA01A18FBA}']
    function GetSearchPaths(const ADprojPath: string): TArray<string>;
    function GetProjectUnits(const ADprojPath: string): TArray<string>;
  end;

  IASTParser = interface
    ['{696D2906-FCBA-429C-A20D-261F8091EAC0}']
    function ParseFile(const AFilePath: string): IUnitSyntaxTree;
  end;
  
  IFileService = interface
    ['{0F09BA45-AE89-4D69-8C03-3D04620A8653}']
    procedure BackupFile(const AFilePath: string);
    procedure RestoreBackups;
    procedure CommitBackups;
    procedure RecoverPendingBackups(const ARootDirectory: string);
    procedure EnsureDirectory(const ADirectory: string);
    function ReadFileContent(const AFilePath: string): string;
    procedure WriteFileContent(const AFilePath: string; const AContent: string);
  end;

  IReportGenerator = interface
    ['{DA4FE6FF-F3D3-433A-ADBE-BD2C344E0EFE}']
    procedure AddUnitProcessed(const AUnitName: string; const ARemovedUses,
      AMovedUses, APreservedAmbiguities: TArray<string>);
    procedure AddMetrics(const ABefore, AAfter: TBuildMetrics);
    procedure AddWarning(const AWarning: string);
    procedure SetAnalysisInfo(const AProjectName: string; AAnalysisTimeMs: Int64; AUnitsAnalyzed, ASearchPaths: Integer);
    function GetReportContentTXT: string;
    function GetReportContentHTML: string;
  end;
  
  IExternalUnitResolver = interface
    ['{946BA138-661C-4B6A-91C9-57BAE3DB3D98}']
    procedure Initialize(const ASearchPaths: TArray<string>; const ADelphiPath, ABasePath: string);
    function GetWarnings: TArray<string>;
    function TryResolveUnit(const AUnitName: string; out AExports: TArray<string>; out AHasInit: Boolean; out AIsNative: Boolean): Boolean;
  end;

  IDelphiEnvironmentService = interface
    ['{F4E5A5A7-1F4F-4C8E-9218-49A322C68A64}']
    function ResolveDelphiPath(const ADprojPath: string): string;
  end;

  IBuildService = interface
    ['{69A27F11-EAA0-4BB1-8F0E-0744743C3A00}']
    function BuildProject(const AProjectPath: string): TBuildMetrics;
    function BuildProjectForTarget(const AProjectPath: string;
      const ATarget: TBuildTarget): TBuildMetrics;
  end;

implementation

constructor TBuildTarget.Create(const AConfiguration, APlatform: string);
begin
  Configuration := AConfiguration;
  Platform := APlatform;
end;

function TBuildTarget.IsValid: Boolean;
begin
  Result := IsValidPart(Configuration) and IsValidPart(Platform);
end;

class function TBuildTarget.IsValidPart(const AValue: string): Boolean;
var
  LCharacter: Char;
begin
  Result := not AValue.IsEmpty;
  if not Result then
    Exit;
  for LCharacter in AValue do
  begin
    Result := CharInSet(LCharacter, ['a'..'z', 'A'..'Z', '0'..'9',
      '_', '-', '.']);
    if not Result then
      Exit;
  end;
end;

class function TBuildTarget.TryParse(const AValue: string;
  out ATarget: TBuildTarget): Boolean;
var
  LSeparatorPosition: Integer;
begin
  LSeparatorPosition := Pos('|', AValue);
  Result := (LSeparatorPosition > 1) and
    (LSeparatorPosition < Length(AValue));
  if not Result then
    Exit;
  Result := Pos('|', AValue, LSeparatorPosition + 1) = 0;
  if not Result then
    Exit;
  ATarget := TBuildTarget.Create(
    Copy(AValue, 1, LSeparatorPosition - 1).Trim,
    Copy(AValue, LSeparatorPosition + 1, MaxInt).Trim);
  Result := ATarget.IsValid;
end;

end.
