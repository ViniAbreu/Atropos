# Testes, cobertura e quality gates

`tests\AtroposTests.dproj` cobre domínio, `.dproj`, DelphiAST, resolução, arquivos, modificador, relatórios, CLI, lifecycle, build e integração.

```powershell
msbuild tests\AtroposTests.dproj /t:Build /p:Config=Debug /p:Platform=Win64
.\tests\Win64\Debug\AtroposTests.exe --consolemode:quiet
```

## Gate completo

Para Win32 e Win64, compila e executa DUnitX, gera CLI/VCL Release e roda smoke real simulado. Depois mede cobertura Win32 e exige o limite.

```powershell
.\tests\run-quality-gates.ps1 `
  -BdsVersion '23.0' `
  -CodeCoveragePath 'D:\Ferramentas\DelphiCodeCoverage\CodeCoverage.exe' `
  -MinimumLineCoverage 85
```

O smoke confere o PE, copia o fixture, executa a CLI, remove uma dependência, gera relatório e garante que o original não mudou.
Ele também solicita explicitamente os targets `Debug|Win32` e `Debug|Win64`,
validando a matriz configurada pelo usuário.

O gate executa ainda os projetos em `tests\Fixtures` nas duas arquiteturas. O
fixture console cobre namespaces, alias `in`, condicionais e
initialization/finalization; o fixture VCL compila um formulário DFM real. Cada
execução ocorre em diretório temporário e confirma que os fixtures versionados
permanecem inalterados.

Somente cobertura:

```powershell
.\tests\run-coverage.ps1 -CodeCoveragePath 'D:\Ferramentas\DelphiCodeCoverage\CodeCoverage.exe' -BdsVersion '23.0' -MinimumLineCoverage 85
```

O workflow `.github\workflows\delphi-quality.yml` requer runner self-hosted Windows com RAD Studio e `DELPHI_CODE_COVERAGE` configurado.
