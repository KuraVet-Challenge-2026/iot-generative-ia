# Scripts

## `smoke-triagem.ps1`: smoke test da triagem com IA no ambiente online

Chama `POST /api/triagens` do app publicado no Azure e mostra se a **extração de sintomas** e a
**orientação** de cada triagem vieram da LLM (Gemini) ou do fallback. O teste passa pelo app inteiro
e não chama a API do Gemini diretamente.

> **Atenção:** cada execução grava **3 triagens reais** no banco de dados. Use sempre um **tutor e um
> pet de demonstração**, nunca dados de clientes reais.

### Pré-requisitos

- PowerShell 7 (`pwsh`) no Windows ou Linux. O Windows PowerShell 5.1 também funciona.
- Um usuário com papel **TUTOR** no app (o endpoint exige `hasRole("TUTOR")`).
- O `idPet` de um pet **desse tutor**. Para outro tutor, a API responde 404.
- O Web App no ar, com as app settings da LLM configuradas (veja [Interpretando o resultado](#interpretando-o-resultado)).

### Senha

A senha é lida **somente** da variável de ambiente `KURAVET_SMOKE_PASSWORD`. Ela não é aceita como
parâmetro, não tem valor padrão e não é gravada em log nem em arquivo.

```powershell
# PowerShell (Windows ou Linux), vale só para a sessão atual
$env:KURAVET_SMOKE_PASSWORD = '<senha do tutor de teste>'
```

```bash
# bash, se for chamar o pwsh a partir dele
read -rs KURAVET_SMOKE_PASSWORD && export KURAVET_SMOKE_PASSWORD
```

Não coloque a senha em arquivo `.env` versionado. O `.gitignore` da raiz bloqueia `.env*`, mas o
mais seguro é não gravá-la em disco.

### Execução

```powershell
pwsh ./scripts/smoke-triagem.ps1 -Usuario <tutor_teste> -PetId <id_pet_demo>
```

| Parâmetro     | Obrigatório | Padrão                                         |
|---------------|-------------|------------------------------------------------|
| `-Usuario`    | sim         | (nenhum)                                       |
| `-PetId`      | sim         | (nenhum)                                       |
| `-BaseUrl`    | não         | `https://kuravet-rm562396.azurewebsites.net`   |
| `-TimeoutSec` | não         | `120` (cobre o cold start do Web App)          |

Para rodar contra o app local: `-BaseUrl http://localhost:8080`. Fora do localhost, o script só aceita `https`.

### Cenários enviados

Os relatos são fixos e foram escritos de acordo com o motor de regras (`MotorRegrasTriagem`). Eles evitam
vômito, diarreia e "não urina", porque esses sintomas fazem a urgência depender da idade (R5) e da espécie
(R2/R3) do pet.

| Cenário      | Sintoma principal | Regra esperada | Urgência esperada |
|--------------|-------------------|----------------|-------------------|
| `baixa`      | espirros          | R8             | BAIXA             |
| `moderada`   | tosse (< 3 dias)  | R7             | MODERADA          |
| `emergencia` | convulsão         | R1             | EMERGENCIA        |

Quem decide a urgência é o motor de regras. A LLM só extrai os sintomas e escreve a orientação. Se a
urgência recebida for diferente da esperada, o script mostra um aviso, mas isso não muda o exit code.

### Saída

O script imprime uma tabela e salva cada resposta, formatada, em `evidencias/api/triagem-<cenario>.json`.
O arquivo guarda só o corpo da resposta, sem headers nem credenciais. Exemplo ilustrativo da tabela:

```
cenário    urgência   metodoExtracao origemOrientacao tempo (ms)
-------    --------   -------------- ---------------- ----------
baixa      BAIXA      LLM            IA_GENERATIVA          3120
moderada   MODERADA   LLM            IA_GENERATIVA          2870
emergencia EMERGENCIA LLM            IA_GENERATIVA          3410
```

### Interpretando o resultado

Campos do `TriagemResponseDTO`:

| Campo              | LLM funcionou   | Fallback          |
|--------------------|-----------------|-------------------|
| `metodoExtracao`   | `LLM`           | `PALAVRAS_CHAVE`  |
| `origemOrientacao` | `IA_GENERATIVA` | `MODELO_FIXO`     |

| Exit code | Significado |
|-----------|-------------|
| `0` | As 3 triagens usaram a LLM na extração **e** na orientação. |
| `1` | Pelo menos uma triagem caiu no fallback. |
| `2` | Erro de execução: senha ausente, 401 (credencial inválida), 403 (usuário sem papel TUTOR), 404 (pet não pertence ao tutor), app inacessível, timeout ou resposta fora do contrato. |

Se o resultado for exit code `1`:

1. Abra **Azure Portal > Web App > Monitoring > Log stream** e procure por `Extração com LLM falhou` ou
   `Orientação com LLM falhou`. O motivo aparece na mesma linha (por exemplo `HTTP 403`, `HTTP 429`, timeout).
2. Em **Settings > Environment variables**, confira as app settings lidas pelo cliente Gemini
   (`kuravet.ia.llm.*` no `application.properties`):
   - `LLM_ENABLED`: se estiver vazia, vale `true`. Com `false`, o app usa sempre o fallback.
   - `LLM_API_KEY`: se estiver vazia, a LLM é considerada indisponível e o app vai direto para o fallback.
   - `LLM_MODEL`: nome do modelo usado no `generateContent`.
