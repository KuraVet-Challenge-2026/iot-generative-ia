#include <Arduino.h>
#include <WiFi.h>
#include <ArduinoJson.h>
#include <DHTesp.h>
#include <PubSubClient.h>

// CONFIGURAÇÕES DE REDE E MQTT
const char *SSID = "Wokwi-GUEST";
const char *PASSWORD = ""; 
const char *BROKER_MQTT = "broker.hivemq.com"; 
const int BROKER_PORT = 1883;
const char *ID_MQTT = "esp32_kuravet_kennel";
const char *TOPIC_PUBLISH_STATUS = "kuravet/leito/status";
const char *TOPIC_SUBSCRIBE_CMD = "kuravet/leito/comando";

// MAPEAMENTO DE PINOS
#define PIN_DHT 12
#define PIN_TRIG 25
#define PIN_ECHO 26
#define PIN_LED_G 22 
#define PIN_LED_R 21 
#define PIN_BUZZER 13

#define PUBLISH_DELAY 3000 

// VARIÁVEIS GLOBAIS 
WiFiClient espClient;
PubSubClient MQTT(espClient);
DHTesp dht;

unsigned long publishUpdate = 0;
TempAndHumidity sensorValues;
long duracao;
int distancia_cm;

// Parâmetros de controle para otimizar envio MQTT
float lastTemperature = NAN;
float lastHumidity = NAN;
int lastDistancia = -1;
bool alertaAtivo = false;

// PROTÓTIPOS
void initWiFi();
void initMQTT();
void callbackMQTT(char *topic, byte *payload, unsigned int length);
void reconnectMQTT();
void checkWiFIAndMQTT();
void readSensors();
void verifyAlerts();

void initWiFi() {
  Serial.print("Conectando ao WiFi: ");
  Serial.println(SSID);
  WiFi.begin(SSID, PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(250);
    Serial.print(".");
  }
  Serial.println("\nWiFi Conectado!");
}

void initMQTT() {
  MQTT.setServer(BROKER_MQTT, BROKER_PORT);
  MQTT.setCallback(callbackMQTT);
}

void reconnectMQTT() {
  while (!MQTT.connected()) {
    Serial.print("Conectando ao Broker MQTT...");
    if (MQTT.connect(ID_MQTT)) {
      Serial.println(" Conectado!");
      MQTT.subscribe(TOPIC_SUBSCRIBE_CMD);
    } else {
      Serial.print(" Falhou, rc=");
      Serial.print(MQTT.state());
      Serial.println(" Tentando em 2s.");
      delay(2000);
    }
  }
}

void checkWiFIAndMQTT() {
  if (WiFi.status() != WL_CONNECTED) initWiFi();
  if (!MQTT.connected()) reconnectMQTT();
}

void callbackMQTT(char *topic, byte *payload, unsigned int length) {
  String msg = String((char*)payload).substring(0, length);
  Serial.printf("Comando recebido no tópico %s: %s\n", topic, msg.c_str());
  
  JsonDocument doc;
  DeserializationError error = deserializeJson(doc, msg);
  
  if (!error && doc["silenciar"].is<bool>()) {
    if (doc["silenciar"] == true) {
      noTone(PIN_BUZZER);
      Serial.println("Alerta silenciado remotamente via Dashboard.");
    }
  }
}

void readSensors() {
  sensorValues = dht.getTempAndHumidity();

  // Leitura 
  digitalWrite(PIN_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(PIN_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(PIN_TRIG, LOW);
  
  duracao = pulseIn(PIN_ECHO, HIGH);
  distancia_cm = duracao * 0.034 / 2;
}

void verifyAlerts() {
  // Temperatura acima de 29°C ou abaixo de 18°C, ou pet muito agitado/perto da grade (distancia < 10cm)
  if (sensorValues.temperature > 29.0 || sensorValues.temperature < 18.0 || distancia_cm < 10) {
    alertaAtivo = true;
    digitalWrite(PIN_LED_G, LOW);
    digitalWrite(PIN_LED_R, HIGH);
    tone(PIN_BUZZER, 1000); 
  } else {
    alertaAtivo = false;
    digitalWrite(PIN_LED_G, HIGH);
    digitalWrite(PIN_LED_R, LOW);
    noTone(PIN_BUZZER);
  }
}

void setup() {
  Serial.begin(115200);

  // Configuração dos Pinos
  pinMode(PIN_TRIG, OUTPUT);
  pinMode(PIN_ECHO, INPUT);
  pinMode(PIN_LED_G, OUTPUT);
  pinMode(PIN_LED_R, OUTPUT);
  pinMode(PIN_BUZZER, OUTPUT);

  // Estado inicial
  digitalWrite(PIN_LED_G, HIGH);
  digitalWrite(PIN_LED_R, LOW);
  noTone(PIN_BUZZER);

  dht.setup(PIN_DHT, DHTesp::DHT22);

  initWiFi();
  initMQTT();
}

void loop() {
  checkWiFIAndMQTT();
  MQTT.loop();

  if ((millis() - publishUpdate) >= PUBLISH_DELAY) {
    publishUpdate = millis();
    
    readSensors();
    verifyAlerts();

    // enviar dados apenas se houver mudança significativa
    bool changed = (abs(sensorValues.temperature - lastTemperature) >= 0.5) ||
                   (abs(sensorValues.humidity - lastHumidity) >= 2.0) ||
                   (abs(distancia_cm - lastDistancia) >= 5);

    if (changed || alertaAtivo) {
      lastTemperature = sensorValues.temperature;
      lastHumidity = sensorValues.humidity;
      lastDistancia = distancia_cm;

      JsonDocument doc;
      doc["temperatura"] = sensorValues.temperature;
      doc["umidade"] = sensorValues.humidity;
      doc["distancia_pet_cm"] = distancia_cm;
      doc["status_alerta"] = alertaAtivo;

      char buffer[256];
      serializeJson(doc, buffer);
      
      MQTT.publish(TOPIC_PUBLISH_STATUS, buffer);
      Serial.print("Dados publicados: ");
      Serial.println(buffer);
    }
  }
}