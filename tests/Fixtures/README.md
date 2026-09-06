# Fixtures representativos

`RepresentativeConsole` valida namespaces, alias `in`, diretivas condicionais,
unit não utilizada e preservação de `initialization`/`finalization`.

`RepresentativeVCL` valida um projeto VCL com formulário DFM real e uma
dependência removível.

`RollbackConsole` força uma falha determinística apenas no segundo build e
confirma que o fonte modificado é restaurado. O fixture console principal também
começa com um backup transacional pendente para validar a recuperação automática.

Os projetos não dependem de componentes comerciais externos. O gate copia cada
fixture para uma pasta temporária, executa o Atropos e confirma build, relatório,
transformação esperada e preservação dos arquivos versionados. Project groups,
packages e DLLs continuam fora do escopo declarado.
