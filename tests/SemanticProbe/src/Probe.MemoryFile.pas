unit Probe.MemoryFile;

interface

uses Atropos.Core.Ports;

type
  // Exercises the real modifier without writing any fixture to disk.
  TProbeMemoryFile = class(TInterfacedObject, IFileService)
  private
    FContent: string;
    FBackup: string;
  public
    constructor Create(const Content: string);
    procedure BackupFile(const FilePath: string);
    procedure RestoreBackups;
    procedure CommitBackups;
    procedure RecoverPendingBackups(const RootDirectory: string);
    procedure EnsureDirectory(const Directory: string);
    function ReadFileContent(const FilePath: string): string;
    procedure WriteFileContent(const FilePath, Content: string);
  end;

implementation

constructor TProbeMemoryFile.Create(const Content: string);
begin
  inherited Create;
  FContent := Content;
end;

procedure TProbeMemoryFile.BackupFile(const FilePath: string);
begin
  FBackup := FContent;
end;

procedure TProbeMemoryFile.RestoreBackups;
begin
  FContent := FBackup;
end;

procedure TProbeMemoryFile.CommitBackups;
begin
  FBackup := '';
end;

procedure TProbeMemoryFile.RecoverPendingBackups(const RootDirectory: string);
begin
end;

procedure TProbeMemoryFile.EnsureDirectory(const Directory: string);
begin
end;

function TProbeMemoryFile.ReadFileContent(const FilePath: string): string;
begin
  Result := FContent;
end;

procedure TProbeMemoryFile.WriteFileContent(const FilePath, Content: string);
begin
  FContent := Content;
end;

end.
