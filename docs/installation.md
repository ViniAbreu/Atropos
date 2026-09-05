# Instalação e compilação

## Requisitos de execução

- Windows;
- RAD Studio/Delphi instalado e registrado;
- projeto `.dproj` compilável no ambiente local;
- acesso de leitura e escrita aos fontes e relatórios.

Baixe Win32 ou Win64 nas [releases](https://github.com/ViniAbreu/Atropos/releases/latest). A arquitetura do Atropos não muda a plataforma configurada no projeto analisado.

## Código-fonte

```powershell
git clone --recurse-submodules https://github.com/ViniAbreu/Atropos.git
cd Atropos
```

Em um clone existente:

```powershell
git submodule update --init --recursive
```

Abra `Atropos.groupproj` ou compile no RAD Studio Command Prompt:

```powershell
msbuild AtroposCLI.dproj /t:Build /p:Config=Release /p:Platform=Win64
msbuild AtroposVCL.dproj /t:Build /p:Config=Release /p:Platform=Win64
```

As saídas ficam em `<plataforma>\<configuração>`. O DelphiAST está em `third_party\DelphiAST`; use o commit do submódulo, não uma instalação global.

## Diagnóstico

- Unit do DelphiAST ausente: inicialize o submódulo.
- RAD Studio não encontrado: confira instalação, registro do BDS e variável `BDS`.
- Build inicial falhou: compile manualmente o mesmo `.dproj` e corrija a linha de base.
- Library Path global muito grande: use os quality gates, que isolam as dependências da build do próprio Atropos.
