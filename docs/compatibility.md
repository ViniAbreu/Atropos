# Compatibilidade

## Validado automaticamente

| Item | Evidência |
| --- | --- |
| Windows Win32 | Build, 84 testes e smoke aprovados |
| Windows Win64 | Build, 84 testes e smoke aprovados |
| RAD Studio BDS 23.0 | Ambiente do quality gate atual |
| DelphiAST | Commit fixado no submódulo |

Isso não certifica todas as combinações de Delphi, componentes e projetos.

O resolvedor reconhece `ProjectVersion` associados a BDS 15.0 até 23.0. Reconhecimento não equivale a validação. Se não houver mapeamento, tenta a maior instalação e depois a variável `BDS`.

O foco atual é `.dproj` Delphi para Windows. Packages, DLLs, services, project groups, projetos multiplataforma e toolchains remotos exigem corpus específico antes de serem declarados suportados.

Uma combinação só deve entrar na matriz validada após builds, DUnitX, smoke isolado e registro da versão/arquitetura no PR.
