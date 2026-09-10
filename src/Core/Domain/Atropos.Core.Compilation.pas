unit Atropos.Core.Compilation;

interface

uses Atropos.Core.Ports;

type
  TCompilerOption = record
    Name: string;
    Value: string;
  end;

  TProjectCompilationContext = record
    ProjectPath: string;
    Target: TBuildTarget;
    MainSource: string;
    CompilerPath: string;
    CompilerFileVersion: string;
    Defines: TArray<string>;
    UnitPaths: TArray<string>;
    SearchPaths: TArray<string>;
    IncludePaths: TArray<string>;
    Namespaces: TArray<string>;
    Aliases: TArray<string>;
    Options: TArray<TCompilerOption>;
    ProjectFiles: TArray<TSourceDependency>;
    DeferredProperties: TArray<string>;
  end;

  IProjectContextProvider = interface
    ['{95EDFD08-7F4D-4D1C-84B4-2271482AD8B4}']
    function EvaluateProject(const AProjectPath, ADelphiPath: string;
      const ATarget: TBuildTarget): TProjectCompilationContext;
  end;

implementation

end.
