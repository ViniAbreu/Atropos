unit Atropos.Core.Ports;

interface

type
  
  IUnitSyntaxTree = interface
    ['{BFA9B996-339A-40C6-90B1-50793D99E416}']
    function GetUnitName: string;
    function GetInterfaceUses: TArray<string>;
    function GetImplementationUses: TArray<string>;
    function GetIdentifiersUsedInInterface: TArray<string>;
    function GetIdentifiersUsedInImplementation: TArray<string>;
    function GetExportedIdentifiers: TArray<string>;
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
    function ReadFileContent(const AFilePath: string): string;
    procedure WriteFileContent(const AFilePath: string; const AContent: string);
  end;

  
  IReportGenerator = interface
    ['{DA4FE6FF-F3D3-433A-ADBE-BD2C344E0EFE}']
    procedure AddUnitProcessed(const AUnitName: string; const ARemovedUses, AMovedUses: TArray<string>);
    function GetReportContent: string;
  end;

  
  IExternalUnitResolver = interface
    ['{946BA138-661C-4B6A-91C9-57BAE3DB3D98}']
    procedure Initialize(const ASearchPaths: TArray<string>; const ADelphiPath, ABasePath: string);
    function TryResolveUnit(const AUnitName: string; out AExports: TArray<string>): Boolean;
  end;

  
  IDelphiEnvironmentService = interface
    ['{F4E5A5A7-1F4F-4C8E-9218-49A322C68A64}']
    function ResolveDelphiPath(const ADprojPath: string): string;
  end;

implementation

end.

