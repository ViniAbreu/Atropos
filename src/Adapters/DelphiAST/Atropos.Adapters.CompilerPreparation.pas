unit Atropos.Adapters.CompilerPreparation;

interface

uses Atropos.Core.Ports, Atropos.Adapters.CompilerBranchTrace;

type
  TCompilerPreparedSource = record
    Text, SourceHash: string;
    Includes: TArray<TCompilerTraceInclude>;
    Dependencies: TArray<TSourceDependency>;
    MissingPaths: TArray<string>;
  end;

  ICompilerSourcePreparer = interface
    ['{7893CC75-610A-4831-A1D8-F2C7860E67C3}']
    // Return only after successful compilation with stable inputs. Text and
    // includes must be normalized for the parser, retaining original paths.
    function Prepare(const AFilePath, AExpectedHash: string): TCompilerPreparedSource;
  end;

implementation

end.
