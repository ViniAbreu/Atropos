# Segurança, backups e rollback

Cada execução é tratada como uma transação:

1. compila o projeto original;
2. se a linha de base falhar, encerra sem alterar fontes;
3. cria backup interno único antes de cada escrita;
4. aplica as transformações;
5. compila novamente;
6. no sucesso, confirma e remove os backups internos;
7. em falha, cancelamento ou exceção, restaura os arquivos.

Backups `.bak` existentes do usuário são preservados. O rollback não substitui Git nem testes funcionais.

## Prática recomendada

- mantenha o worktree limpo e versionado;
- execute uma instância por projeto;
- revise o diff e rode os testes do projeto;
- faça backup externo se não houver controle de versão.

O AutoBuild usa `bds.exe`. Processos filhos são reunidos em um Windows Job Object para encerramento conjunto; o timeout padrão é de 10 minutos.

## Script legado

`clean_and_move_uses.ps1`, na raiz, não faz parte do fluxo seguro. Ele apaga `.bak` recursivamente e altera fontes sem a mesma verificação e rollback. Não o use em produção.
