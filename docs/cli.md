# Referência da CLI

```text
AtroposCLI.exe -dproj <arquivo.dproj> [opções]
```

| Opção | Efeito |
| --- | --- |
| `-dproj <arquivo>` | Projeto analisado; obrigatória, exceto com ajuda. |
| `--remove` | Remove units classificadas como não utilizadas. |
| `--move` | Move para `implementation` as units usadas somente nela. |
| `-html` | Grava `AtroposReport.html`. |
| `-txt` | Grava `AtroposReport.txt`. |
| `--output <diretório>` | Pasta dos relatórios; caminho relativo parte da pasta do `.dproj`. |
| `--debug` | Habilita diagnóstico detalhado. |
| `--help`, `-h`, `/?` | Exibe ajuda. |

Sem `--output`, relatórios solicitados são gravados ao lado do projeto. O resumo textual também aparece no console sem `-txt`.

## Códigos de saída

| Código | Significado |
| --- | --- |
| `0` | Sucesso, inclusive sem mudanças necessárias. |
| `1` | Falha operacional, de build final ou exceção. |
| `2` | Opção inválida, valor ausente ou projeto inexistente. |

```powershell
& .\AtroposCLI.exe -dproj $project --remove -txt --output reports
if ($LASTEXITCODE -ne 0) { throw "Atropos falhou: $LASTEXITCODE" }
```

Não há `--dry-run` nem cancelamento próprio da CLI. Comece em uma branch limpa, revise o diff e não execute duas instâncias sobre os mesmos fontes.
