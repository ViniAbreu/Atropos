# Arquitetura

```text
CLI / VCL -> Application Service -> Core (domínio e ports)
                                      ^
                                      |
          Adapters (AST, XML, arquivos, build, ambiente, relatório)
```

## Camadas

- `src\Core`: modelos, configuração, regras, modificador e ports. Não conhece UI ou infraestrutura.
- `src\Application`: orquestra ambiente, builds, análise, commit, rollback, logs e progresso.
- `src\Adapters`: integra DelphiAST, `.dproj`, units externas, arquivos, BDS, registro e relatórios.
- `src\CLI` e `src\GUI`: contratos de apresentação sobre o mesmo serviço de aplicação.

Adapters e apresentação dependem das abstrações do Core. O domínio não deve importar VCL, XML, registro, filesystem ou DelphiAST. Novas integrações devem implementar uma port e ser conectadas pela factory.

Responsabilidades principais dos adapters:

- `DelphiAST`: visão sintática dos fontes;
- `ProjectParser`: propriedades condicionais, units e search paths;
- `ExternalUnitResolver`: localização e símbolos exportados;
- `FileSystem`: I/O e transação de backups;
- `BuildService`: AutoBuild, timeout, cancelamento e métricas;
- `DelphiEnvironment`: versão do projeto e instalação do RAD Studio;
- `ReportGenerator`: texto e HTML.
