# Tabela de Regras da Triagem (motor determinístico)

> Fonte da verdade: `br.com.fiap.kuravet.ia.MotorRegrasTriagem` (repo `java-advanced`).
> A LLM (ou o extrator por palavras-chave) apenas extrai os sintomas do relato.
> **Quem decide a urgência é exclusivamente este motor de regras** — determinístico e auditável.

## Entradas

- **Sintomas extraídos** (conjunto): `VOMITO, DIARREIA, FALTA_DE_APETITE, APATIA, FEBRE, TOSSE, ESPIRROS, COCEIRA, FERIDA, MANCANDO, DIFICULDADE_RESPIRAR, CONVULSAO, SANGRAMENTO, INGESTAO_TOXICA, NAO_URINA, DESMAIO`.
- **Duração** (dias), quando o relato informa.
- **Perfil do pet:**
  - `isFilhote` → idade < 1 ano
  - `isIdoso` → idade ≥ 10 anos
  - `isGato` → espécie normalizada (minúsculas, sem acento) igual a `gato`

## Regras (da mais grave para a mais leve)

| Código | Condição | Urgência |
|---|---|---|
| **R1** | Qualquer sinal de emergência: dificuldade para respirar, convulsão, sangramento, ingestão tóxica **ou** desmaio | **EMERGENCIA** |
| **R2** | **Gato** que não urina (risco de obstrução urinária) | **EMERGENCIA** |
| **R3** | Não urina, em espécie **diferente** de gato | **ALTA** |
| **R4** | Vômito **e** diarreia juntos | **ALTA** |
| **R5** | Filhote **ou** idoso **com** vômito ou diarreia | **ALTA** |
| **R6** | Febre **com** apatia | **ALTA** |
| **R7** | Qualquer sintoma que exige acompanhamento: vômito, diarreia, falta de apetite, apatia, febre, tosse, ferida ou mancando | **MODERADA** |
| **R8** | Coceira **ou** espirros | **BAIXA** |

## Resolução e escalonamento

- **Várias regras podem disparar ao mesmo tempo.** A urgência final é a **maior** entre todas as regras disparadas.
- **R9 (escalonamento por persistência):** se a urgência resolvida for `MODERADA` **e** a duração informada for **≥ 3 dias**, sobe para `ALTA`.
- **R10 (sem sintomas):** se nenhum sintoma for reconhecido no relato, a urgência é `BAIXA` com orientação para descrever melhor os sintomas.

## Recomendações por urgência

| Urgência | Recomendação |
|---|---|
| EMERGENCIA | Procure atendimento presencial imediato em um pronto-socorro veterinário. |
| ALTA | Solicite uma teleconsulta prioritária ainda hoje. |
| MODERADA | Agende uma teleconsulta nas próximas 48 horas e observe a evolução. |
| BAIXA | Observe por 48 horas; se surgirem novos sintomas, refaça a triagem. |

> Toda recomendação termina com o aviso: *"Esta triagem é orientativa e não substitui a avaliação do veterinário."*

## Limitações conhecidas

- `isFilhote`/`isIdoso` usam limiares fixos (1 e 10 anos) para todas as espécies — simplificação; porte/raça não são considerados.
- `isGato` compara a espécie de forma exata com `gato`; espécie em texto livre ("Gato Persa", "Felino") não é reconhecida como gato (ver `avaliacao/resultados.md`, caso C03).
