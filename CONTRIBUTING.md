# Contribuindo

Clone com `--recurse-submodules`, crie uma branch focada e leia [arquitetura](docs/architecture.md), [testes](docs/testing.md) e [segurança](docs/safety-and-rollback.md).

## Regras

- Preserve a direção de dependências da arquitetura hexagonal.
- Não coloque I/O, VCL, XML ou DelphiAST no Core.
- Correções devem ter teste que falhe sem a correção.
- Funcionalidades devem cobrir comportamento nominal e falhas relevantes.
- Escritas em fontes devem provar rollback e preservação de encoding.
- Não dependa desnecessariamente de bibliotecas globais.
- Atualize a documentação afetada.

Antes do PR:

```powershell
.\tests\run-quality-gates.ps1 `
  -BdsVersion '23.0' `
  -CodeCoveragePath 'D:\Ferramentas\DelphiCodeCoverage\CodeCoverage.exe' `
  -MinimumLineCoverage 85
```

Informe problema, decisão técnica, riscos, testes, resultados Win32/Win64, cobertura e validações manuais. Prefira uma frente por PR e não misture mudanças não relacionadas.

Contribuições são distribuídas sob a licença GPL-3.0 do projeto.
