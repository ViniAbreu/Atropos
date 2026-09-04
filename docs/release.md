# Processo de release

Publique somente a partir de `main` limpa e com todos os PRs dependentes integrados.

## Checklist

1. Atualizar versão e release notes.
2. Conferir o commit do submódulo DelphiAST.
3. Executar o quality gate completo.
4. Confirmar DUnitX, builds e smokes Win32/Win64.
5. Confirmar cobertura acima do limite.
6. Gerar `Atropos-<versão>-Win32.zip` e `Atropos-<versão>-Win64.zip`.
7. Publicar checksums SHA-256.
8. Assinar executáveis quando houver certificado.
9. Documentar mudanças, limitações e compatibilidade.
10. Testar os pacotes baixados em máquina limpa.

O pipeline atual valida o código; publicação automática e assinatura ainda não estão implementadas.
