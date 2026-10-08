#include <WiFi.h>
#include <esp_wifi.h>
#include <esp_now.h>

#define WIFI_CH 1
uint8_t bcast[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
uint32_t seq = 0;

void setup() {
  Serial.begin(115200);
  WiFi.mode(WIFI_STA);
  esp_wifi_set_channel(WIFI_CH, WIFI_SECOND_CHAN_NONE);
  if (esp_now_init() != ESP_OK) { Serial.println("ESP-NOW gagal"); while (1) delay(1000); }
  esp_now_peer_info_t peer = {};
  memcpy(peer.peer_addr, bcast, 6);
  peer.channel = WIFI_CH;
  peer.encrypt = false;
  esp_now_add_peer(&peer);
  Serial.print("TX siap, MAC: "); Serial.println(WiFi.macAddress());
}

void loop() {
  static uint32_t t = millis();
  if (millis() - t >= 20) {
    t += 20;
    esp_now_send(bcast, (uint8_t *)&seq, sizeof(seq));
    seq++;
  }
}
