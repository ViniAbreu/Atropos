unit Atropos.Core.Compilation;

interface

uses Atropos.Core.Ports;

type
  TUnitSourceMapping = record
    UnitName: string;
    FilePath: string;
  end;

  IProjectSourceImports = interface
    ['{5CCA6010-8074-4FC7-85EF-566022BF9D74}']
    function GetProjectImports: TArray<TUnitSourceMapping>;
  end;

  TCompilerOption = record
    Name: string;
    Value: string;
  end;

  TProjectCompilationContext = record
    ProjectPath: string;
    Target: TBuildTarget;
    MainSource: string;
    ExecutablePath: string;
    ApplicationType: string;
    CompilerPath: string;
    CompilerFileVersion: string;
    CompilerContextHash: string;
    Defines: TArray<string>;
    UnitPaths: TArray<string>;
    SourceMappings: TArray<TUnitSourceMapping>;
    SearchPaths: TArray<string>;
    IncludePaths: TArray<string>;
    ResourcePaths: TArray<string>;
    ObjectPaths: TArray<string>;
    Namespaces: TArray<string>;
    Aliases: TArray<string>;
    Options: TArray<TCompilerOption>;
    ProjectFiles: TArray<TSourceDependency>;
    DeferredProperties: TArray<string>;
  end;

  TCompilerSymbols = record
    Defines: TArray<string>;
    CompilerVersion: string;
    DefaultSwitches: TArray<TCompilerOption>;
    NumericValues: TArray<TCompilerOption>;
  end;

  TTargetAnalysisServices = record
    // The factory starts the snapshot before reading project sources.
    Parser: IASTParser;
    Resolver: IExternalUnitResolver;
    UnitPaths: TArray<string>;
  end;

  ITargetAnalysisFactory = interface
    ['{87E2DBD9-532F-47D9-98E6-76F590EBF8A2}']
    function CreateForTarget(const AContext: TProjectCompilationContext;
      const ADelphiPath: string): TTargetAnalysisServices;
  end;

  IProjectSnapshotInputs = interface
    ['{420633F7-EC82-4D15-A879-CF80EAF94A15}']
    procedure RegisterProjectInputs(const AFiles: TArray<TSourceDependency>);
  end;

  IProjectContextProvider = interface
    ['{95EDFD08-7F4D-4D1C-84B4-2271482AD8B4}']
    function EvaluateProject(const AProjectPath, ADelphiPath: string;
      const ATarget: TBuildTarget): TProjectCompilationContext;
  end;

implementation

end.
