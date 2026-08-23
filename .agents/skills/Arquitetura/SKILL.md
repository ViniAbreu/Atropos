---
name: Arquitetura e Engenharia de Software
description: Diretrizes obrigatórias de arquitetura de software, design patterns e clean code para todo o projeto.
---

# Diretrizes de Arquitetura e Engenharia de Software

Sempre que estiver escrevendo, refatorando ou analisando código neste projeto, você **DEVE** seguir rigorosamente os princípios abaixo:

## 1. SOLID
- **SRP (Single Responsibility Principle):** Cada classe e método deve ter uma única responsabilidade.
- **OCP (Open/Closed Principle):** As classes devem estar abertas para extensão, mas fechadas para modificação.
- **LSP (Liskov Substitution Principle):** Classes derivadas devem poder substituir suas classes base sem quebrar o sistema.
- **ISP (Interface Segregation Principle):** Crie interfaces pequenas e específicas para o cliente, em vez de interfaces genéricas.
- **DIP (Dependency Inversion Principle):** Dependa de abstrações (Interfaces/Ports) e não de implementações concretas (Adapters). Injeção de dependência é fundamental.

## 2. Arquitetura Hexagonal (Ports and Adapters)
- O **Core/Domínio** e os **Application Services** são o centro da aplicação e não devem ter nenhuma dependência de bibliotecas externas, UI ou I/O.
- Comunicação com o mundo externo (FileSystem, DelphiAST, CLI, VCL, XML, MSBuild) deve ser feita através de **Ports** (Interfaces definidas no Core).
- As implementações reais dessas interfaces devem ficar restritas à camada de **Adapters** (Infraestrutura/Apresentação).
- O fluxo de dependência é sempre de Fora (Adapters) para Dentro (Core). O Core não conhece os Adapters.

## 3. DRY (Don't Repeat Yourself)
- Nunca duplique lógica ou blocos de código.
- Se uma mesma sequência de código (como uma iteração de projeto, formatação de path, lógicas de tratamento de erros) existir na CLI e na VCL, extraia-a imediatamente para um Application Service ou camada compartilhada.
- Centralize constantes, paths mágicos e definições repetitivas.

## 4. Object Calisthenics
- **Apenas um nível de indentação por método:** Se precisar de mais, extraia para outro método.
- **Tolerância Zero para `else`:** NENHUM fluxo lógico deve usar `else`. Aplique *early return* (cláusulas de guarda / guard clauses) com `Exit()` ou `Continue` de forma absoluta.
- **Proibição Estrita de Sub-funções (Nested Routines):** Toda lógica auxiliar deve ser declarada como um método privado (ou helper) da classe, nunca aninhada dentro de outra função ou procedure.
- **Envolva tipos primitivos e strings:** Crie Value Objects para representar domínios específicos (ex: `TUnitPath` ao invés de apenas `string` caso possua regras atreladas).
- **Coleções de Primeira Classe (First Class Collections):** Qualquer array ou lista genérica que exija manipulação de lógica de negócio deve ser encapsulada em uma classe própria.
- **Um ponto (ou acesso) por linha:** Respeite a Lei de Demeter (não acesse `A.B.C.D()`).
- **Não abrevie:** Nomes de variáveis e métodos devem expressar sua intenção claramente.
- **Mantenha as classes pequenas:** Máximo recomendado de 50 linhas de código limpo (quando possível).
- **Sem Getters/Setters desnecessários:** Exponha comportamento (Tell, Don't Ask) ao invés de apenas expor estado.

## 5. KISS (Keep It Simple, Stupid)
- A solução mais simples que funcione e atenda aos requisitos de negócios, arquitetura e testes é sempre a melhor escolha.
- Evite abstrações precoces (over-engineering). Crie abstrações apenas quando o domínio pedir ou para respeitar a Arquitetura Hexagonal.
- Escreva código legível por humanos antes de tentar escrever código hiper-otimizado (a menos que a performance seja um gargalo documentado).
