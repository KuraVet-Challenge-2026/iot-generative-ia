<#
.SYNOPSIS
    Smoke test ponta a ponta da triagem com IA do KuraVet no ambiente online.

.DESCRIPTION
    Envia 3 relatos fixos para POST /api/triagens (HTTP Basic, papel TUTOR) e verifica,
    pelos campos metodoExtracao e origemOrientacao da resposta, se a extracao de sintomas
    e a orientacao vieram da LLM (Gemini) ou do fallback.

    Contrato (repo java-advanced, pacote br.com.fiap.kuravet):
      request : TriagemRequestDTO  { idPet, relato }
      response: TriagemResponseDTO { ..., urgencia, metodoExtracao (LLM | PALAVRAS_CHAVE),
                                     orientacao, origemOrientacao (IA_GENERATIVA | MODELO_FIXO) }

    A senha vem SOMENTE da variavel de ambiente KURAVET_SMOKE_PASSWORD.
    ATENCAO: cada execucao grava 3 triagens reais no banco. Use um pet de demonstracao.

    Exit codes:
      0 = as 3 triagens usaram a LLM na extracao e na orientacao
      1 = alguma triagem caiu no fallback
      2 = erro de execucao (senha ausente, 401/403/404, app fora do ar, resposta inesperada)

.EXAMPLE
    $env:KURAVET_SMOKE_PASSWORD = '<senha>'
    pwsh ./scripts/smoke-triagem.ps1 -Usuario tutor.demo -PetId 1
#>
[CmdletBinding()]
param(
    [string] $BaseUrl = 'https://kuravet-rm562396.azurewebsites.net',

    [Parameter(Mandatory = $true)]
    [string] $Usuario,

    [Parameter(Mandatory = $true)]
    [long] $PetId,

    # Generoso por causa do cold start do Web App + timeout de 8 s de cada chamada ao Gemini.
    [int] $TimeoutSec = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Settings lidas pelo GeminiProperties (kuravet.ia.llm.*) via application.properties.
$SettingsLlm = @('LLM_ENABLED', 'LLM_API_KEY', 'LLM_MODEL')

# Relatos coerentes com o MotorRegrasTriagem. Nenhum cita vomito/diarreia, para nao
# depender da idade do pet (R5), nem "nao urina", para nao depender da especie (R2/R3).
$Cenarios = @(
    [pscustomobject]@{
        Nome     = 'baixa'
        Esperada = 'BAIXA'      # R8 - espirros
        Relato   = 'Meu pet está espirrando algumas vezes desde ontem, mas continua comendo, bebendo água e brincando normalmente.'
    },
    [pscustomobject]@{
        Nome     = 'moderada'
        Esperada = 'MODERADA'   # R7 - tosse, ha menos de 3 dias (sem R9)
        Relato   = 'Desde ontem à noite meu pet está com uma tosse seca de vez em quando, mas segue ativo e se alimentando bem.'
    },
    [pscustomobject]@{
        Nome     = 'emergencia'
        Esperada = 'EMERGENCIA' # R1 - convulsao
        Relato   = 'Meu pet teve uma convulsão agora há pouco, ficou se debatendo e babando por quase dois minutos e continua desorientado.'
    }
)

function Stop-Smoke([string] $Mensagem) {
    Write-Host "ERRO: $Mensagem" -ForegroundColor Red
    exit 2
}

function Write-JsonUtf8([string] $Caminho, [string] $Conteudo) {
    # UTF-8 sem BOM, igual no Windows PowerShell 5.1 e no PowerShell 7.
    [System.IO.File]::WriteAllText($Caminho, $Conteudo + "`n", (New-Object System.Text.UTF8Encoding($false)))
}

$senha = $env:KURAVET_SMOKE_PASSWORD
if ([string]::IsNullOrEmpty($senha)) {
    Stop-Smoke ("Variável de ambiente KURAVET_SMOKE_PASSWORD não definida.`n" +
        "      Defina antes de rodar:  `$env:KURAVET_SMOKE_PASSWORD = '<senha do tutor de teste>'")
}

$baseUri = $null
if (-not [System.Uri]::TryCreate($BaseUrl.TrimEnd('/'), [System.UriKind]::Absolute, [ref] $baseUri) -or
        $baseUri.Scheme -notin @('http', 'https')) {
    Stop-Smoke "BaseUrl inválida: '$BaseUrl'"
}
if ($baseUri.Scheme -eq 'http' -and $baseUri.Host -notin @('localhost', '127.0.0.1')) {
    Stop-Smoke 'HTTP Basic sem TLS só é permitido para localhost. Use https.'
}
$endpoint = "$($baseUri.AbsoluteUri.TrimEnd('/'))/api/triagens"

if ($PSVersionTable.PSVersion.Major -lt 6) {
    Add-Type -AssemblyName System.Net.Http
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

$pastaEvidencias = Join-Path (Split-Path -Parent $PSScriptRoot) 'evidencias/api'
New-Item -ItemType Directory -Force -Path $pastaEvidencias | Out-Null

$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
$token = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${Usuario}:$senha"))
$client.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Basic', $token)
$client.DefaultRequestHeaders.Accept.ParseAdd('application/json')
Remove-Variable senha, token

Write-Host "Smoke test da triagem: POST $endpoint (usuário '$Usuario', pet $PetId)"
Write-Host 'Aviso: cada execução grava 3 triagens reais no banco.' -ForegroundColor Yellow
Write-Host ''

$resultados = @()
try {
    foreach ($c in $Cenarios) {
        $corpo = @{ idPet = $PetId; relato = $c.Relato } | ConvertTo-Json -Compress
        $conteudo = New-Object System.Net.Http.StringContent($corpo, [System.Text.Encoding]::UTF8, 'application/json')

        $cronometro = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $resposta = $client.PostAsync($endpoint, $conteudo).GetAwaiter().GetResult()
        } catch [System.Threading.Tasks.TaskCanceledException] {
            Stop-Smoke "Timeout de $TimeoutSec s no cenário '$($c.Nome)'. O Web App pode estar parado ou em cold start."
        } catch {
            $causa = $_.Exception
            while ($causa.InnerException) { $causa = $causa.InnerException }
            Stop-Smoke "Não foi possível conectar em $($baseUri.Host): $($causa.Message)"
        }
        $cronometro.Stop()

        $status = [int] $resposta.StatusCode
        # Le os bytes e decodifica como UTF-8: o Spring nem sempre manda charset no Content-Type.
        $bytes = $resposta.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        $texto = [System.Text.Encoding]::UTF8.GetString($bytes)

        switch ($status) {
            201 { }
            401 { Stop-Smoke "HTTP 401: usuário ou senha inválidos para '$Usuario'. Confira KURAVET_SMOKE_PASSWORD." }
            403 { Stop-Smoke "HTTP 403: '$Usuario' autenticou, mas não tem o papel TUTOR exigido por POST /api/triagens." }
            404 { Stop-Smoke "HTTP 404: pet $PetId não encontrado para o tutor '$Usuario' (ou URL errada: $endpoint)." }
            default {
                $detalhe = ''
                try { $detalhe = ($texto | ConvertFrom-Json).mensagem } catch { }
                Stop-Smoke "HTTP $status no cenário '$($c.Nome)'. $detalhe"
            }
        }

        try {
            $json = $texto | ConvertFrom-Json
        } catch {
            Stop-Smoke "Resposta do cenário '$($c.Nome)' não é JSON (HTTP $status). A URL aponta para o app KuraVet?"
        }
        foreach ($campo in @('urgencia', 'metodoExtracao', 'origemOrientacao')) {
            if (-not ($json.PSObject.Properties.Name -contains $campo)) {
                Stop-Smoke "Resposta do cenário '$($c.Nome)' sem o campo '$campo'. O contrato do TriagemResponseDTO mudou?"
            }
        }

        # Somente o corpo da resposta: sem headers e sem credenciais.
        Write-JsonUtf8 (Join-Path $pastaEvidencias "triagem-$($c.Nome).json") ($json | ConvertTo-Json -Depth 10)

        $resultados += [pscustomobject]@{
            'cenário'          = $c.Nome
            'urgência'         = $json.urgencia
            'metodoExtracao'   = $json.metodoExtracao
            'origemOrientacao' = $json.origemOrientacao
            'tempo (ms)'       = $cronometro.ElapsedMilliseconds
            Esperada           = $c.Esperada
        }
    }
} finally {
    $client.Dispose()
}

$resultados | Format-Table 'cenário', 'urgência', 'metodoExtracao', 'origemOrientacao', 'tempo (ms)' -AutoSize | Out-Host

foreach ($r in $resultados) {
    if ($r.'urgência' -ne $r.Esperada) {
        Write-Host ("Aviso: cenário '$($r.'cenário')' esperava urgência $($r.Esperada) e recebeu $($r.'urgência'). " +
            'Confira os sintomas extraídos no JSON.') -ForegroundColor Yellow
    }
}
Write-Host "Respostas salvas em $pastaEvidencias"

$fallback = @($resultados | Where-Object { $_.metodoExtracao -ne 'LLM' -or $_.origemOrientacao -ne 'IA_GENERATIVA' })
if ($fallback.Count -eq 0) {
    Write-Host 'OK: as 3 triagens usaram a LLM (metodoExtracao=LLM, origemOrientacao=IA_GENERATIVA).' -ForegroundColor Green
    exit 0
}

Write-Host ''
Write-Host "FALHA: $($fallback.Count) de $($resultados.Count) triagem(ns) caíram no fallback " -ForegroundColor Red -NoNewline
Write-Host "($((@($fallback | ForEach-Object { $_.'cenário' })) -join ', '))." -ForegroundColor Red
Write-Host @"
Próximos passos:
  1. Azure Portal > Web App > Monitoring > Log stream: procure por
     'Extração com LLM falhou' ou 'Orientação com LLM falhou' (o motivo vem na mesma linha).
  2. Azure Portal > Web App > Settings > Environment variables: confira as app settings
     lidas pelo cliente Gemini: $($SettingsLlm -join ', ')
     (LLM_ENABLED vazio = true; LLM_API_KEY vazia = LLM desligada).
"@
exit 1
