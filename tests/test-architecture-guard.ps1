$ErrorActionPreference = 'Stop'
$guardPath = Join-Path $PSScriptRoot 'test-architecture.ps1'
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ("AtroposArchitectureGuard-" + [guid]::NewGuid().ToString('N'))

function Write-Fixture([string]$RelativePath, [string[]]$Content) {
    $path = Join-Path $fixtureRoot $RelativePath
    $directory = Split-Path $path -Parent
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    Set-Content -LiteralPath $path -Value $Content -Encoding UTF8
}

function Assert-GuardFailure([string]$ExpectedMessage) {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $guardPath `
        -SourceRoot $fixtureRoot 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { throw "Guard unexpectedly accepted: $ExpectedMessage" }
    if (-not $output.Contains($ExpectedMessage)) {
        throw "Guard failure did not contain '$ExpectedMessage': $output"
    }
}

try {
    Write-Fixture 'Core\Valid.pas' @('unit Valid;', 'interface',
        'uses System.SysUtils;', 'implementation', 'procedure Run;', 'begin',
        'end;', 'end.')
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $guardPath `
        -SourceRoot $fixtureRoot | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Guard rejected the valid fixture.' }

    Write-Fixture 'Core\InvalidElse.pas' @('unit InvalidElse;', 'interface',
        'implementation', 'procedure Run;', 'begin', '  if True then',
        '    Exit', '  else', '    Exit;', 'end;', 'end.')
    Assert-GuardFailure 'contains else'
    Remove-Item -LiteralPath (Join-Path $fixtureRoot 'Core\InvalidElse.pas')

    Write-Fixture 'Core\InvalidDependency.pas' @('unit InvalidDependency;',
        'interface', 'uses Atropos.Adapters.FileSystem;', 'implementation', 'end.')
    Assert-GuardFailure 'forbidden Core dependency'
    Remove-Item -LiteralPath (Join-Path $fixtureRoot 'Core\InvalidDependency.pas')

    Write-Fixture 'Application\InvalidNested.pas' @('unit InvalidNested;',
        'interface', 'implementation', 'procedure Run;', '  procedure Nested;',
        '  begin', '  end;', 'begin', 'end;', 'end.')
    Assert-GuardFailure 'nested named routine'
    Remove-Item -LiteralPath (Join-Path $fixtureRoot 'Application\InvalidNested.pas')

    Write-Fixture 'Application\InvalidDependency.pas' @('unit InvalidDependency;',
        'interface', 'uses Vcl.Forms;', 'implementation', 'end.')
    Assert-GuardFailure 'forbidden Application dependency'
    Remove-Item -LiteralPath (Join-Path $fixtureRoot 'Application\InvalidDependency.pas')

    Write-Fixture 'Adapters\InvalidDependency.pas' @('unit InvalidDependency;',
        'interface', 'uses Atropos.VCL.Main;', 'implementation', 'end.')
    Assert-GuardFailure 'forbidden Adapters dependency'
    Remove-Item -LiteralPath (Join-Path $fixtureRoot 'Adapters\InvalidDependency.pas')

    Write-Fixture 'Core\TooLarge.pas' ((1..601) | ForEach-Object { '// line' })
    Assert-GuardFailure 'exceeds 600 file lines'
    Remove-Item -LiteralPath (Join-Path $fixtureRoot 'Core\TooLarge.pas')

    $longRoutine = @('unit LongRoutine;', 'interface', 'implementation',
        'procedure LongRun;', 'begin') +
        @((1..118) | ForEach-Object { '  // line' }) +
        @('end;', 'procedure NextRun;', 'begin', 'end;', 'end.')
    Write-Fixture 'Core\LongRoutine.pas' $longRoutine
    Assert-GuardFailure 'routine exceeds 120 lines'
} finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}

$global:LASTEXITCODE = 0
Write-Host 'Architecture guard regression tests passed.'
