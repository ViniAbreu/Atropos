# Limitações conhecidas

- Não há modo `dry-run` ou geração de diff sem escrita.
- A VCL não exporta relatório nem escolhe diretório de saída.
- A CLI não tem opção própria de cancelamento.
- A análise depende das units e search paths obtidos do `.dproj`.
- Dependências não localizadas são preservadas conservadoramente.
- Inicialização e referências condicionais podem impedir alterações.
- RTTI dinâmica, carregamento por nome, side effects e código gerado podem escapar da análise estática.
- Library Paths e componentes globais podem variar entre máquinas.
- A validação atual concentra-se em Windows e BDS 23.0.
- UI visual e todas as versões reais do RAD Studio não estão integralmente cobertas.

Em produção, use uma branch, revise todas as mudanças e rode a suíte funcional do projeto analisado.
