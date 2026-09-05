# Interface VCL

Execute `AtroposVCL.exe`, selecione um `.dproj` e escolha:

- **Remove Unused:** remove dependências não utilizadas;
- **Move to Implementation:** move dependências usadas apenas na implementação;
- **Enable Debug Logging:** detalha o processamento.

Clique em **Iniciar Limpeza**. A barra acompanha as units e o painel registra builds e decisões. **Cancelar** solicita interrupção segura; a janela não fecha enquanto a execução estiver ativa. Cancelamentos e exceções restauram os backups da transação.

## Limitação atual

A VCL ainda não expõe relatório HTML/TXT nem diretório de saída. Use a CLI para persistir relatórios; o resumo textual aparece no painel de log.
