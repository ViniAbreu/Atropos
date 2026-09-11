unit Atropos.Adapters.CompilerContextSignature;

interface

type
  TCompilerContextSignature = class
  public
    class function Script: string; static;
  end;

implementation

uses System.SysUtils;

class function TCompilerContextSignature.Script: string;
begin
  Result :=
    'function Read-CompilerContextHash($contextProject) {' + sLineBreak +
    ' $values = [ordered]@{}' + sLineBreak +
    ' $names = @($contextProject.Properties | Where-Object { $_.Name -match ''^(DCC_|BDS$|Config$|Platform$|UnitSearchPath$|IncludePath$|ResourcePath$|_ObjectPath$|UnitAliases$|AppType$|MainSource$|SyntaxCheck$|OutputExt$)'' } | ForEach-Object { $_.Name } | Sort-Object -Unique)' + sLineBreak +
    ' foreach ($name in $names) { $values[$name] = $contextProject.GetPropertyValue($name) }' + sLineBreak +
    ' $compiler = ''dcc32.exe''' + sLineBreak +
    ' if ($contextProject.GetPropertyValue(''Platform'') -eq ''Win64'') { $compiler = ''dcc64.exe'' }' + sLineBreak +
    ' $algorithm = [Security.Cryptography.SHA256]::Create()' + sLineBreak +
    ' try {' + sLineBreak +
    '  foreach ($relative in @((''bin\'' + $compiler), (''bin64\'' + $compiler), ''bin\Borland.Build.Tasks.Delphi.dll'', ''bin\Borland.Build.Tasks.Shared.dll'')) {' + sLineBreak +
    '   $path = [IO.Path]::Combine($env:BDS, $relative)' + sLineBreak +
    '   $value = ''missing''' + sLineBreak +
    '   if ([IO.File]::Exists($path)) {' + sLineBreak +
    '    $stream = [IO.File]::OpenRead($path)' + sLineBreak +
    '    try { $value = [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace(''-'', '''') } finally { $stream.Dispose() }' + sLineBreak +
    '   }' + sLineBreak +
    '   $values[''tool:'' + $path] = $value' + sLineBreak +
    '  }' + sLineBreak +
    '  $json = $values | ConvertTo-Json -Depth 4 -Compress' + sLineBreak +
    '  return [BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).Replace(''-'', '''')' + sLineBreak +
    ' } finally { $algorithm.Dispose() }' + sLineBreak +
    '}';
end;

end.
