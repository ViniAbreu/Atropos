unit Atropos.Adapters.CompilerSymbols;

interface

uses Atropos.Core.Ports, Atropos.Core.Compilation, Atropos.Adapters.BuildService;

type
  TCompilerSymbolReader = class
  private
    FRunner: IBuildProcessRunner;
    FCancel: TCancellationCheck;
    function ApplicationSwitch(const AContext: TProjectCompilationContext): string;
    function ProbeSource(const AContext: TProjectCompilationContext): string;
    function Compile(const AContext: TProjectCompilationContext;
      const ADelphiPath, ADirectory, ASourcePath: string): string;
    function ParseOutput(const AOutput: string): TCompilerSymbols;
  public
    constructor Create(const ARunner: IBuildProcessRunner;
      const ACancel: TCancellationCheck);
    function Read(const AContext: TProjectCompilationContext;
      const ADelphiPath: string): TCompilerSymbols;
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils, System.RegularExpressions,
  System.Generics.Collections;

constructor TCompilerSymbolReader.Create(const ARunner: IBuildProcessRunner;
  const ACancel: TCancellationCheck);
begin
  inherited Create;
  FRunner := ARunner;
  FCancel := ACancel;
end;

function TCompilerSymbolReader.ProbeSource(
  const AContext: TProjectCompilationContext): string;
const
  CSymbols = 'WIN32;WIN64;MSWINDOWS;CPU386;CPUX86;CPUX64;CPU32BITS;CPU64BITS;' +
    'CONSOLE;NATIVECODE;CONDITIONALEXPRESSIONS;UNICODE;ALIGN_STACK;ASSEMBLER;' +
    'AUTOREFCOUNT;EXTERNALLINKER;ELF;NEXTGEN;PC_MAPPED_EXCEPTIONS;PIC;' +
    'UNDERSCOREIMPORTNAME;WEAKREF;WEAKINSTREF;WEAKINTFREF;DYNAMICBASE;' +
    'LINUX;LINUX32;LINUX64;POSIX;POSIX32;POSIX64;MACOS;MACOS32;MACOS64;' +
    'IOS;IOS32;IOS64;ANDROID;ANDROID32;ANDROID64;CPUARM;CPUARM32;CPUARM64;' +
    'ARM_NO_VFP_USE';
var LSymbol: string;
begin
  Result := 'program AtroposCompilerContext;' + sLineBreak +
    '{$HINTS ON}' + sLineBreak;
  for LSymbol in CSymbols.Split([';']) do
    Result := Result + '{$IFDEF ' + LSymbol + '}' +
      '{$MESSAGE HINT ''ATROPOS_DEFINE:' + LSymbol + '''}{$ENDIF}' + sLineBreak;
  Result := Result + 'begin end.';
end;

function TCompilerSymbolReader.ApplicationSwitch(
  const AContext: TProjectCompilationContext): string;
var LOption: TCompilerOption;
begin
  if not SameText(AContext.ApplicationType, 'Console') and
    not SameText(AContext.ApplicationType, 'Application') then
    raise EInvalidOperation.Create('Unsupported application type: ' + AContext.ApplicationType);
  Result := '-CG';
  if SameText(AContext.ApplicationType, 'Console') then
    Result := '-CC';
  for LOption in AContext.Options do
  begin
    if not SameText(LOption.Name, 'ConsoleTarget') then
      Continue;
    if SameText(LOption.Value, 'true') then
      Result := '-CC';
    if SameText(LOption.Value, 'false') then
      Result := '-CG';
  end;
end;

function TCompilerSymbolReader.Compile(const AContext: TProjectCompilationContext;
  const ADelphiPath, ADirectory, ASourcePath: string): string;
var
  LCommand, LLibrary: string;
  LCode: Cardinal;
  LTimeout, LCancelled: Boolean;
begin
  if not SameText(AContext.Target.Platform, 'Win32') and
    not SameText(AContext.Target.Platform, 'Win64') then
    raise EInvalidOperation.Create('Compiler symbol probing supports Win32 and Win64 only.');
  if not TFile.Exists(AContext.CompilerPath) then
    raise EFileNotFoundException.Create('Compiler not found: ' + AContext.CompilerPath);
  LLibrary := TPath.Combine(ADelphiPath, 'lib\' + AContext.Target.Platform + '\release');
  LCommand := Format('"%s" %s -B -E"%s" -N0"%s" -U"%s" "%s"',
    [AContext.CompilerPath, ApplicationSwitch(AContext), ADirectory, ADirectory, LLibrary, ASourcePath]);
  if not FRunner.Execute(LCommand, 60000, FCancel, Result, LCode, LTimeout, LCancelled) then
    raise EInvalidOperation.Create('Cannot start compiler symbol probe: ' + Result);
  if LCancelled then
    raise EAbort.Create('Compiler symbol probe cancelled.');
  if LTimeout then
    raise EInvalidOperation.Create('Compiler symbol probe timed out.');
  if LCode <> 0 then
    raise EInvalidOperation.Create('Compiler symbol probe failed: ' + Result);
end;

function TCompilerSymbolReader.ParseOutput(const AOutput: string): TCompilerSymbols;
var
  LNames: TList<string>;
  LMatch: TMatch;
  LName: string;
begin
  LMatch := TRegEx.Match(AOutput, 'compiler version (\d+\.\d+)', [roIgnoreCase]);
  if not LMatch.Success then
    raise EInvalidOperation.Create('Compiler probe did not identify its language version.');
  Result.CompilerVersion := LMatch.Groups[1].Value;
  LNames := TList<string>.Create;
  try
    for LMatch in TRegEx.Matches(AOutput, 'ATROPOS_DEFINE:([A-Z0-9_]+)') do
    begin
      LName := LMatch.Groups[1].Value;
      if not LNames.Contains(LName) then
        LNames.Add(LName);
    end;
    if not LNames.Contains('MSWINDOWS') then
      raise EInvalidOperation.Create('Compiler probe returned no Windows platform symbols.');
    LNames.Add('VER' + Result.CompilerVersion.Replace('.', ''));
    Result.Defines := LNames.ToArray;
  finally
    LNames.Free;
  end;
end;

function TCompilerSymbolReader.Read(const AContext: TProjectCompilationContext;
  const ADelphiPath: string): TCompilerSymbols;
var
  LDirectory, LSource, LFile: string;
begin
  LDirectory := TPath.Combine(TPath.GetTempPath, 'Atropos-Symbols-' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(LDirectory);
  try
    LSource := TPath.Combine(LDirectory, 'AtroposCompilerContext.dpr');
    TFile.WriteAllText(LSource, ProbeSource(AContext), TEncoding.UTF8);
    Result := ParseOutput(Compile(AContext, ADelphiPath, LDirectory, LSource));
  finally
    for LFile in TDirectory.GetFiles(LDirectory) do
      TFile.Delete(LFile);
    TDirectory.Delete(LDirectory);
  end;
end;

end.
