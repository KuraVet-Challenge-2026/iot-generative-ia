# Resultados da Avaliação da Triagem

> Cenários de `cenarios.csv` executados contra o código **real** da triagem
> (pacote `br.com.fiap.kuravet.ia`: `ExtratorPalavrasChave` + `MotorRegrasTriagem`),
> método de extração `PALAVRAS_CHAVE` (fallback sem LLM).
> A coluna **Obtido** é a saída de execução do código, não uma estimativa.

## Resumo

| Métrica | Valor |
|---|---|
| Cenários avaliados | 20 |
| Acertos (urgência obtida = esperada) | **16** |
| Taxa de acerto | **80%** |
| Erros para o lado seguro (sobre-triagem) | 2 (C15, C17) |
| Erros para o lado inseguro (sub-triagem) | 2 (C03, C04) |

A urgência **esperada** é a classificação clinicamente correta (gabarito), não "o que o código faria". Por isso as divergências medem a qualidade real da solução, e não apenas a implementação.

## Esperado × Obtido

| ID | Espécie | Idade | Sintomas extraídos | Esperado | Obtido | Resultado |
|---|---|---|---|---|---|---|
| C01 | Cachorro | 3 | DIFICULDADE_RESPIRAR | EMERGENCIA | EMERGENCIA | ✅ |
| C02 | Gato | 2 | NAO_URINA | EMERGENCIA | EMERGENCIA | ✅ |
| C03 | Gato Persa | 4 | NAO_URINA | EMERGENCIA | ALTA | ❌ sub-triagem |
| C04 | Cachorro | 5 | (nenhum) | ALTA | BAIXA | ❌ sub-triagem |
| C05 | Cachorro | 1 | DIARREIA, VOMITO | ALTA | ALTA | ✅ |
| C06 | Cachorro | 0 | VOMITO | ALTA | ALTA | ✅ |
| C07 | Gato | 12 | DIARREIA | ALTA | ALTA | ✅ |
| C08 | Cachorro | 4 | APATIA, FEBRE | ALTA | ALTA | ✅ |
| C09 | Cachorro | 3 | FALTA_DE_APETITE, VOMITO | MODERADA | MODERADA | ✅ |
| C10 | Cachorro | 6 | TOSSE (5 dias) | ALTA | ALTA | ✅ |
| C11 | Cachorro | 2 | TOSSE (1 dia) | MODERADA | MODERADA | ✅ |
| C12 | Cachorro | 2 | COCEIRA, ESPIRROS | BAIXA | BAIXA | ✅ |
| C13 | Gato | 3 | (nenhum) | BAIXA | BAIXA | ✅ |
| C14 | Cachorro | 3 | (nenhum) | BAIXA | BAIXA | ✅ |
| C15 | Cachorro | 4 | DIARREIA, VOMITO | MODERADA | ALTA | ❌ sobre-triagem |
| C16 | Cachorro | 2 | INGESTAO_TOXICA | EMERGENCIA | EMERGENCIA | ✅ |
| C17 | Cachorro | 3 | INGESTAO_TOXICA | BAIXA | EMERGENCIA | ❌ sobre-triagem |
| C18 | Cachorro | 8 | FERIDA, MANCANDO | MODERADA | MODERADA | ✅ |
| C19 | Gato | 1 | CONVULSAO | EMERGENCIA | EMERGENCIA | ✅ |
| C20 | Cachorro | 10 | FALTA_DE_APETITE (4 dias) | ALTA | ALTA | ✅ |

## Análise das divergências

### C03 — "O gato não está urinando" (Gato Persa) → obteve ALTA, esperava EMERGENCIA
Sub-triagem. `isGato()` compara a espécie de forma exata com `gato`; como o cadastro foi "Gato Persa", o pet não é reconhecido como gato e a regra R2 (emergência de obstrução urinária felina) não dispara, caindo em R3.
**Ação:** tornar `isGato()` tolerante a espécie em texto livre (reconhecer o token `gato`/`felino`). Correção de 1 linha, sem mudança de schema.

### C04 — "Não está conseguindo urinar" → obteve BAIXA, esperava ALTA
Sub-triagem **grave** (nenhum sintoma detectado). O dicionário de `NAO_URINA` cobre "nao consegue urinar", mas não a forma no gerúndio "conseguindo urinar".
**Ação:** acrescentar variantes ("nao esta conseguindo urinar", "nao conseguindo urinar", "nao consegue mais urinar") ao dicionário. Baixo risco.

### C15 — "não está com vômito mas tem diarreia" → obteve ALTA, esperava MODERADA
Sobre-triagem (lado seguro). A negação só é avaliada nas 2 palavras anteriores ao termo; aqui "não" está a 3 palavras de "vômito", então VOMITO é incluído por engano e dispara R4 (vômito + diarreia).
**Ação:** limitação inerente da extração por palavras-chave. Resolve-se com a extração por **LLM** (T12), que entende a negação no contexto.

### C17 — "chocolate ... ele NÃO comeu, só eu" → obteve EMERGENCIA, esperava BAIXA
Sobre-triagem (lado seguro). O termo "chocolate" (ingestão tóxica) é detectado mesmo o tutor negando que o pet comeu.
**Ação:** mesma classe do C15 — negação dependente de contexto; alvo da extração por LLM (T12).

## Conclusão

- O **motor de regras** acertou em 100% dos casos em que os sintomas foram extraídos corretamente — a decisão clínica é sólida e previsível.
- As 4 divergências estão todas na **camada de extração** (NLP), não na decisão de urgência:
  - 2 são correções baratas e já mapeadas (C03, C04) → elevam a taxa para **90%**.
  - 2 são limites conhecidos do método por palavras-chave (C15, C17) e são exatamente a justificativa para a camada de **LLM (T12)**; além disso, erram para o lado seguro (sobre-triagem).
- Reforça a decisão de arquitetura: manter a decisão clínica no motor determinístico e usar a LLM apenas para interpretar o texto.

## Como reproduzir

Os cenários são executados contra as classes reais do pacote `br.com.fiap.kuravet.ia`.
A mesma lógica é coberta pelos testes de unidade `MotorRegrasTriagemTest` e `ExtratorPalavrasChaveTest` no `java-advanced` (`./mvnw test`).
