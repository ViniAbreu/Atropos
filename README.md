# Atropos

Otimizador de cláusulas `uses` para projetos Delphi. O Atropos analisa as units de um `.dproj`, remove dependências não utilizadas e pode mover dependências da `interface` para a `implementation`.

Antes de modificar fontes, compila o projeto para estabelecer uma linha de base. Depois das alterações, compila novamente e confirma ou desfaz a operação conforme o resultado.

> O Atropos modifica código-fonte. Use controle de versão, revise o diff produzido e leia o [modelo de segurança](docs/safety-and-rollback.md) antes do primeiro uso.

## Estado atual

- CLI e interface VCL para Windows.
- Builds nativos Win32 e Win64 validados.
- 84 testes automatizados executados nas duas arquiteturas.
- Smoke tests de compilação, modificação, relatório e preservação do fixture.
- Cobertura protegida por gate mínimo de 85%.
- DelphiAST fixado como submódulo Git.

Consulte a [matriz de compatibilidade](docs/compatibility.md) para separar ambientes validados de versões apenas reconhecidas pelo resolvedor.

## Início rápido

Obtenha os executáveis nas [releases](https://github.com/ViniAbreu/Atropos/releases/latest) ou siga o [guia de instalação](docs/installation.md).

```powershell
AtroposCLI.exe -dproj "C:\Projetos\MinhaAplicacao\MinhaAplicacao.dproj" --remove --move -html -txt
AtroposCLI.exe -dproj "C:\Projetos\MinhaAplicacao\MinhaAplicacao.dproj" --remove -txt --output reports
```

Sem `--remove` ou `--move`, nenhuma alteração é solicitada, embora a compilação inicial ainda seja executada.

## Documentação

- [Instalação e compilação](docs/installation.md)
- [Referência da CLI](docs/cli.md)
- [Interface VCL](docs/gui.md)
- [Segurança e rollback](docs/safety-and-rollback.md)
- [Testes e cobertura](docs/testing.md)
- [Arquitetura](docs/architecture.md)
- [Compatibilidade](docs/compatibility.md)
- [Limitações conhecidas](docs/known-limitations.md)
- [Processo de release](docs/release.md)
- [Como contribuir](CONTRIBUTING.md)

## Fluxo

1. Lê configurações, units e search paths ativos do `.dproj`.
2. Localiza o RAD Studio e compila o projeto original.
3. Analisa os fontes com DelphiAST.
4. Cria backups transacionais antes de escrever.
5. Aplica somente as opções selecionadas.
6. Recompila e confirma as mudanças ou restaura os arquivos.
7. Exibe o resumo e, quando solicitado pela CLI, grava TXT e/ou HTML.

Casos considerados inseguros são preservados de forma conservadora. Veja as [limitações](docs/known-limitations.md).

## Licença

[GNU General Public License v3.0](LICENSE).
