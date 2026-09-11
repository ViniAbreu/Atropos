unit Context.Consumer;
interface
uses Context.Unused, OldDep, NamespaceProvider, Mapped,
  {$IFDEF WIN64}Context.Platform64{$ELSE}Context.Platform32{$ENDIF},
  {$IFDEF PROJECT_DEBUG}Context.DebugOnly{$ELSE}Context.ReleaseOnly{$ENDIF};
procedure Run;
implementation
procedure Run;
begin
  Writeln(AliasValue, '|', NamespaceValue, '|', MappedValue, '|', PlatformValue, '|', DefineValue);
end;
end.
