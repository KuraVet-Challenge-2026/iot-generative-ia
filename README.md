# KuraVet - Smart Kennel (Leito Inteligente) 🐾

Este repositório contém a entrega do 1º Sprint da disciplina Disruptive Architectures: IOT, IOB & Generative IA para o ecossistema KuraVet.

## 🎯 O Problema
Em clínicas veterinárias, pets internados ou em recuperação pós-cirúrgica necessitam de repouso e de um ambiente com temperatura controlada. A falta de monitoramento contínuo pode levar a estresse térmico ou complicações devido à agitação excessiva do animal. 

A solução **Smart Kennel** utiliza IoT para monitorar o ambiente (temperatura/umidade) e o repouso do pet (distância/agitação), alertando os veterinários em tempo real em caso de anomalias, garantindo a integridade do índice de vitalidade do ecossistema KuraVet.

## 🛠️ Tecnologias Utilizadas e Justificativa
* **ESP32:** Microcontrolador com Wi-Fi nativo, ideal para aplicações IoT de baixo custo e alta eficiência.
* **Sensor DHT22:** Monitoramento preciso de temperatura e umidade para garantir a climatização do leito.
* **Sensor Ultrassônico (HC-SR04):** Posicionado estrategicamente para medir a distância do pet. Variações constantes indicam agitação, enquanto medidas estáticas indicam repouso.
* **Protocolo MQTT (HiveMQ):** Protocolo leve e assíncrono, perfeito para enviar telemetria em tempo real das clínicas para o nosso backend na nuvem.
* **Wokwi:** Plataforma de simulação que nos permitiu validar a prova de conceito de hardware antes da montagem física.

## 🚀 Como testar a simulação
1. Acesse o nosso projeto no Wokwi através deste link: `[https://wokwi.com/projects/463770290208231425]`
2. Clique no botão **Play** (verde) para iniciar a simulação.
3. Aguarde o terminal exibir `WiFi Conectado!` e `Conectado ao Broker MQTT...`.
4. **Interação:** Clique no sensor DHT22 e altere a temperatura para mais de 29°C, ou clique no sensor HC-SR04 e altere a distância para menos de 10cm. 
5. O alarme (Buzzer + LED Vermelho) será acionado e o log enviará o status de alerta via MQTT.

## 📹 Vídeo de Apresentação (Pitch)
Assista à nossa demonstração técnica e explicação do projeto:
`[COLE O LINK DO VÍDEO DO YOUTUBE AQUI]`

## 📁 Estrutura do Projeto
- `/src/main.cpp`: Código-fonte em C++ com a lógica de sensores, atuadores e comunicação MQTT.
- `diagram.json`: Estrutura do circuito simulado no Wokwi.
- `platformio.ini`: Arquivo de dependências para rodar o projeto localmente no VS Code.