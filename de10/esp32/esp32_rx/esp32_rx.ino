#include <WiFi.h>
#include <esp_wifi.h>
#include <esp_now.h>

#define WIFI_CH     1
#define FPGA_TX_PIN 17
#define FPGA_RX_PIN 16
#define SC_INDEX    20

uint8_t tx_mac[6] = {0, 0, 0, 0, 0, 0};

volatile int8_t   csi_i = 0, csi_q = 0;
volatile bool     csi_new = false;
volatile uint32_t csi_count = 0;

static bool mac_ok(const uint8_t *m) {
  bool any = true;
  for (int k = 0; k < 6; k++) if (tx_mac[k]) any = false;
  return any || memcmp(m, tx_mac, 6) == 0;
}

void csi_cb(void *ctx, wifi_csi_info_t *info) {
  if (!info || !info->buf || !mac_ok(info->mac)) return;
  int idx = SC_INDEX * 2;
  if (info->len < idx + 2) return;
  csi_q = info->buf[idx];
  csi_i = info->buf[idx + 1];
  csi_new = true;
  csi_count++;
}

void espnow_rx(const esp_now_recv_info_t *info, const uint8_t *data, int len) {
}

uint32_t csi_rate() {
  static uint32_t t0 = 0, c0 = 0, rate = 0;
  uint32_t now = millis();
  if (now - t0 >= 1000) { rate = csi_count - c0; c0 = csi_count; t0 = now; }
  return rate;
}

void setup() {
  Serial.begin(115200);
  Serial2.begin(115200, SERIAL_8N1, FPGA_RX_PIN, FPGA_TX_PIN);

  WiFi.mode(WIFI_STA);
  esp_wifi_set_channel(WIFI_CH, WIFI_SECOND_CHAN_NONE);
  esp_now_init();
  esp_now_register_recv_cb(espnow_rx);

  wifi_csi_config_t cfg = {};
  cfg.lltf_en           = true;
  cfg.htltf_en          = false;
  cfg.stbc_htltf2_en    = false;
  cfg.ltf_merge_en      = true;
  cfg.channel_filter_en = false;
  cfg.manu_scale        = false;
  esp_wifi_set_csi_config(&cfg);
  esp_wifi_set_csi_rx_cb(csi_cb, NULL);
  esp_wifi_set_csi(true);

  Serial.print("RX siap, MAC: "); Serial.println(WiFi.macAddress());
}

void loop() {
  if (csi_new) {
    csi_new = false;
    uint8_t i = (uint8_t)csi_i, q = (uint8_t)csi_q;
    uint8_t frame[5] = {0xAA, 0x55, i, q, (uint8_t)(i ^ q)};
    Serial2.write(frame, 5);
  }

  static String line;
  while (Serial2.available()) {
    char c = Serial2.read();
    if (c == '\n') {
      int s = line.length() > 1 ? line[1] - '0' : -1;
      const char *nama = s == 0 ? "KOSONG" : s == 1 ? "ORANG DIAM" : s == 2 ? "ORANG BERGERAK" : "?";
      Serial.printf("FPGA: %s  -> %s  (CSI/detik ~%lu)\n", line.c_str(), nama, (unsigned long)csi_rate());
      line = "";
    } else if (c != '\r') line += c;
  }
}
