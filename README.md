# Wi-CARE

WiFi Contactless Activity and Respiration Engine.

- `cyclone4/` : prototipe Cyclone IV + ESP32 (UART), tanpa HPS
- `de10/`     : sistem lengkap DE10-Nano (FPGA + HPS + server)

Data `csi_data.hex` adalah data sintetis untuk pengujian. Ganti dengan rekaman ESP32
(per baris `IIQQ`, int8 hex), lalu kalibrasi ulang ambang `T_MOT` dan `T_BR`.

## cyclone4

| File | Isi |
| --- | --- |
| `wicare_lite.v` | pipeline CSI |
| `wicare_top.v` | top level board |
| `uart_rx.v`, `uart_tx.v`, `csi_frame_rx.v`, `report_tx.v` | antarmuka ESP32 |
| `tb_wicare.v`, `run.do` | simulasi pipeline |
| `tb_top.v`, `run_top.do` | simulasi board |
| `gen_csi.py` | data uji dan golden model |
| `pins_cyclone4.tcl` | pin (sesuaikan dengan board) |
| `replay_uart.py` | uji board lewat USB-UART |

Simulasi (ModelSim, dari folder `cyclone4`):

```
do run.do
do run_top.do
```

Quartus: top-level `wicare_top`, file `wicare_top.v uart_rx.v uart_tx.v csi_frame_rx.v
report_tx.v wicare_lite.v wicare_top.sdc`. Pin di `pins_cyclone4.tcl` adalah contoh untuk
EP4CE6E22C8; `PIN_XX`/`PIN_YY` diisi pin header untuk UART. Jika LED board aktif HIGH,
set parameter `LED_ACTIVE_LOW` = 0.

Wiring: ESP32 GPIO17 -> `uart_rx_pin`, GPIO16 <- `uart_tx_pin`, GND bersama.
LED: [0] kosong, [1] diam, [2] bergerak, [3] data masuk.

Frame ESP32 -> FPGA: `AA 55 I Q CHK`, `CHK = I ^ Q`.
Laporan FPGA -> ESP32: `S<status> M<mot hex> B<br hex>`.

## de10

| Folder | Isi |
| --- | --- |
| `rtl/` | `wicare_avalon.v` (komponen Avalon), `wicare_pipe.v`, `ascon_tag.v`, `key_prov.v`, UART |
| `sim/` | `run_ascon.do`, `run_de10.do`, `verify_reports.py` |
| `quartus/` | `wicare_hw.tcl` (Platform Designer), `top_snippet.v`, `resource_check/` |
| `hps/` | `wicare_daemon.c` |
| `server/` | `server_dashboard.py`, `provision_key.py`, `test_server.py` |
| `esp32/` | firmware pemancar dan penerima |

### Simulasi

```
cd de10/sim
do run_ascon.do
do run_de10.do
python verify_reports.py
```

### Register map

Alamat HPS = `0xFF200000` + base komponen (default `0x10000`).

| Offset | Nama | Akses | Isi |
| --- | --- | --- | --- |
| 0x00 | CTRL | W | [0] reset pipeline, [1] clear report_ready |
| 0x04 | STATUS | R | [1:0] status, [8] report_ready, [9] key_valid, [10] busy, [11] src_hps, [31:16] versi |
| 0x08 | CSI_IN | W | [15:8] I, [7:0] Q (mode benchmark) |
| 0x0C | CONFIG | RW | [7:0] room, [23:8] report_every, [24] src_hps |
| 0x10 | T_MOT | RW | ambang gerak |
| 0x14 | T_BR | RW | ambang napas |
| 0x18 / 0x1C | SESS_LO / SESS_HI | RW | session id |
| 0x20 / 0x24 | MOT / BR | R | fitur |
| 0x28 / 0x2C | CSI_OK / CSI_ERR | R | jumlah frame |
| 0x30 | R_CNT | R | counter laporan |
| 0x34 | R_INFO | R | [7:0] room, [15:8] status, [23:16] flags |
| 0x38 | R_FEAT | R | [15:0] mot, [31:16] br |
| 0x3C | R_THR | R | [15:0] t_mot, [31:16] t_br |
| 0x40..0x4C | TAG | R | tag 16 byte |
| 0x50 | DROPPED | R | laporan terlewat |

Format laporan (AD Ascon, 15 byte, little-endian):
`room | counter(4) | status | mot(2) | br(2) | t_mot(2) | t_br(2) | flags`.
Nonce: `session(8) | counter(4) | room | 00 00 00`.

### Quartus

Cek resource: buka `quartus/resource_check/wicare_resource.qpf`, Start Compilation.

Integrasi penuh (proyek `DE10_NANO_SoC_GHRD`):

1. Salin `rtl/` dan `quartus/wicare_hw.tcl` ke folder proyek.
2. Platform Designer: tambahkan Wi-CARE. `clock`/`reset` ke `clk_0`, `s0` ke
   `hps_0.h2f_lw_axi_master` (base `0x0001_0000`), `irq0` ke `hps_0.f2h_irq0`,
   export `pins` sebagai `wicare_pins`.
3. Generate HDL, tambahkan isi `top_snippet.v` ke top-level, compile.
4. Konversi `.sof` ke `.rbf`, salin ke microSD sebagai `soc_system.rbf`.

Wiring: ESP32 GPIO17 -> `GPIO_0[0]`, USB-UART TX (provisioning) -> `GPIO_0[1]`, GND bersama.

### Menjalankan

Laptop/server:

```
pip install pyserial
python provision_key.py COM6
python server_dashboard.py --key key.hex
```

DE10-Nano (root):

```
make
./wicare_daemon run -s <IP server>
./wicare_daemon bench csi_data.hex
```

Dashboard: `http://<IP server>:8080`. File `key.hex` hanya disimpan di server.
Kunci hilang setiap FPGA reset; kirim ulang dengan `provision_key.py COM6 --reuse`.
