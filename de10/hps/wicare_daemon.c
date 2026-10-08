#define _GNU_SOURCE
#include <arpa/inet.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define LW_BRIDGE_BASE 0xFF200000u
#define MAP_SPAN       0x1000u

#define R_CTRL     0x00
#define R_STATUS   0x04
#define R_CSI_IN   0x08
#define R_CONFIG   0x0C
#define R_T_MOT    0x10
#define R_T_BR     0x14
#define R_SESS_LO  0x18
#define R_SESS_HI  0x1C
#define R_MOT      0x20
#define R_BR       0x24
#define R_CSI_OK   0x28
#define R_CSI_ERR  0x2C
#define R_R_CNT    0x30
#define R_R_INFO   0x34
#define R_R_FEAT   0x38
#define R_R_THR    0x3C
#define R_TAG0     0x40
#define R_DROPPED  0x50

static volatile uint32_t *regs;

static inline uint32_t rd(uint32_t off) { return regs[off / 4]; }
static inline void wr(uint32_t off, uint32_t v) { regs[off / 4] = v; }

static double now_s(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec * 1e-9;
}

static int map_fpga(uint32_t offset) {
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) { perror("open /dev/mem (jalankan sebagai root)"); return -1; }
    void *p = mmap(NULL, MAP_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED, fd,
                   LW_BRIDGE_BASE + offset);
    close(fd);
    if (p == MAP_FAILED) { perror("mmap"); return -1; }
    regs = (volatile uint32_t *)p;
    uint32_t ver = rd(R_STATUS) >> 16;
    if (ver != 0x0100) {
        fprintf(stderr, "Versi komponen tidak cocok (baca 0x%04x). Cek offset -b dan bitstream.\n", ver);
        return -1;
    }
    return 0;
}

typedef struct {
    int32_t s_fast, s_slow, mot, br;
    int cand_prev, cnt, status, first;
} pipe_t;

static void pipe_init(pipe_t *p) { memset(p, 0, sizeof *p); p->first = 1; }

static int pipe_step(pipe_t *p, int8_t i, int8_t q, int t_mot, int t_br) {
    int32_t pwr = (int32_t)i * i + (int32_t)q * q;
    int32_t x8 = pwr << 8;
    if (p->first) { p->s_fast = p->s_slow = x8; p->first = 0; }
    p->s_fast += (x8 - p->s_fast) >> 3;
    p->s_slow += (x8 - p->s_slow) >> 8;
    int32_t yf = p->s_fast >> 8, ys = p->s_slow >> 8;
    int32_t hp = pwr - yf, bp = yf - ys;
    p->mot += ((hp < 0 ? -hp : hp) - p->mot) >> 4;
    p->br  += ((bp < 0 ? -bp : bp) - p->br)  >> 6;
    int cand = p->mot > t_mot ? 2 : (p->br > t_br ? 1 : 0);
    if (cand != p->cand_prev) p->cnt = 0;
    else if (p->cnt < 25) p->cnt++;
    p->cand_prev = cand;
    if (p->cnt == 25) p->status = cand;
    return p->status;
}

static inline uint64_t ror(uint64_t x, int n) { return (x >> n) | (x << (64 - n)); }

static void ascon_perm(uint64_t s[5], int rounds) {
    for (int r = 12 - rounds; r < 12; r++) {
        uint64_t x0 = s[0], x1 = s[1], x2 = s[2], x3 = s[3], x4 = s[4], t0, t1, t2, t3, t4;
        x2 ^= (uint64_t)(0xF0 - r * 0x0F);
        x0 ^= x4; x4 ^= x3; x2 ^= x1;
        t0 = ~x0 & x1; t1 = ~x1 & x2; t2 = ~x2 & x3; t3 = ~x3 & x4; t4 = ~x4 & x0;
        x0 ^= t1; x1 ^= t2; x2 ^= t3; x3 ^= t4; x4 ^= t0;
        x1 ^= x0; x0 ^= x4; x3 ^= x2; x2 = ~x2;
        s[0] = x0 ^ ror(x0, 19) ^ ror(x0, 28);
        s[1] = x1 ^ ror(x1, 61) ^ ror(x1, 39);
        s[2] = x2 ^ ror(x2, 1)  ^ ror(x2, 6);
        s[3] = x3 ^ ror(x3, 10) ^ ror(x3, 17);
        s[4] = x4 ^ ror(x4, 7)  ^ ror(x4, 41);
    }
}

static void ascon_tag_sw(const uint64_t k[2], const uint64_t n[2], const uint64_t ad[2], uint64_t t[2]) {
    uint64_t s[5] = {0x00001000808C0001ull, k[0], k[1], n[0], n[1]};
    ascon_perm(s, 12);
    s[3] ^= k[0]; s[4] ^= k[1];
    s[0] ^= ad[0]; s[1] ^= ad[1];
    ascon_perm(s, 8);
    s[4] ^= 0x8000000000000000ull;
    s[0] ^= 1;
    s[2] ^= k[0]; s[3] ^= k[1];
    ascon_perm(s, 12);
    t[0] = s[3] ^ k[0]; t[1] = s[4] ^ k[1];
}

static int load_csi(const char *path, int8_t **I, int8_t **Q) {
    FILE *f = fopen(path, "r");
    if (!f) { perror(path); return -1; }
    int cap = 8192, n = 0;
    *I = malloc(cap); *Q = malloc(cap);
    unsigned v;
    while (fscanf(f, "%x", &v) == 1) {
        if (n == cap) { cap *= 2; *I = realloc(*I, cap); *Q = realloc(*Q, cap); }
        (*I)[n] = (int8_t)(v >> 8); (*Q)[n] = (int8_t)(v & 0xFF); n++;
    }
    fclose(f);
    return n;
}

static int cmd_bench(const char *csi_path, int sw_only, const char *golden, uint32_t off,
                     int t_mot, int t_br) {
    int8_t *I, *Q;
    int n = load_csi(csi_path, &I, &Q);
    if (n <= 0) return 1;
    int *sw = malloc(n * sizeof(int));
    printf("Data: %d paket CSI dari %s\n\n", n, csi_path);

    const int REP = 200;
    pipe_t p;
    double t0 = now_s();
    for (int r = 0; r < REP; r++) {
        pipe_init(&p);
        for (int k = 0; k < n; k++) sw[k] = pipe_step(&p, I[k], Q[k], t_mot, t_br);
    }
    double t_sw = (now_s() - t0) / ((double)REP * n);

    uint64_t key[2] = {1, 2}, non[2] = {3, 4}, ad[2] = {5, 6}, tg[2];
    const int NT = 20000;
    t0 = now_s();
    for (int r = 0; r < NT; r++) { non[1] = r; ascon_tag_sw(key, non, ad, tg); }
    double t_tag = (now_s() - t0) / NT;

    printf("SOFTWARE (ARM):\n");
    printf("  pipeline        : %8.1f ns per paket CSI\n", t_sw * 1e9);
    printf("  Ascon tag       : %8.1f ns per laporan\n", t_tag * 1e9);

    if (golden) {
        FILE *g = fopen(golden, "r");
        if (!g) { perror(golden); return 1; }
        int bad = 0; unsigned v;
        for (int k = 0; k < n && fscanf(g, "%x", &v) == 1; k++) if ((int)v != sw[k]) bad++;
        fclose(g);
        printf("  cek golden      : %s (%d beda)\n", bad ? "FAIL" : "PASS", bad);
    }
    if (sw_only) return 0;

    if (map_fpga(off)) return 1;
    uint32_t cfg = rd(R_CONFIG);
    wr(R_T_MOT, t_mot); wr(R_T_BR, t_br);
    wr(R_CONFIG, (cfg & 0x00FFFFFF) | (1u << 24));
    wr(R_CTRL, 1);
    int agree = 0;
    t0 = now_s();
    for (int k = 0; k < n; k++) {
        wr(R_CSI_IN, ((uint8_t)I[k] << 8) | (uint8_t)Q[k]);
        if ((int)(rd(R_STATUS) & 3) == sw[k]) agree++;
    }
    double t_hw = (now_s() - t0) / n;
    wr(R_CONFIG, cfg & 0x00FFFFFF);
    wr(R_CTRL, 3);
    printf("\nHARDWARE (FPGA, termasuk akses bus dari ARM):\n");
    printf("  pipeline        : %8.1f ns per paket CSI\n", t_hw * 1e9);
    printf("  Ascon tag       : 32 clock = 640 ns pada 50 MHz, tanpa beban CPU\n");
    printf("  kecocokan status: %d/%d paket sama dengan software\n", agree, n);
    printf("\nCatatan: di mode produksi CSI masuk FPGA langsung dari ESP32,\n"
           "jadi beban CPU HPS untuk pipeline dan Ascon = 0.\n");
    return 0;
}

static int cmd_run(uint32_t off, const char *ip, int port, int room, int every, int t_mot, int t_br) {
    if (map_fpga(off)) return 1;

    uint64_t session = 0;
    FILE *ur = fopen("/dev/urandom", "rb");
    if (!ur || fread(&session, 8, 1, ur) != 1) { fprintf(stderr, "gagal baca /dev/urandom\n"); return 1; }
    fclose(ur);

    wr(R_SESS_LO, (uint32_t)session);
    wr(R_SESS_HI, (uint32_t)(session >> 32));
    wr(R_T_MOT, t_mot);
    wr(R_T_BR, t_br);
    wr(R_CONFIG, (uint32_t)room | ((uint32_t)every << 8));
    wr(R_CTRL, 3);

    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in dst = {0};
    dst.sin_family = AF_INET;
    dst.sin_port = htons(port);
    inet_pton(AF_INET, ip, &dst.sin_addr);

    const char *nama[] = {"KOSONG", "ORANG DIAM", "ORANG BERGERAK", "?"};
    printf("Wi-CARE daemon: room %d, session %016llx, server %s:%d\n",
           room, (unsigned long long)session, ip, port);
    if (!((rd(R_STATUS) >> 9) & 1))
        printf("PERINGATAN: kunci belum di-provision. FPGA tidak akan membuat laporan.\n");

    double t_info = now_s();
    for (;;) {
        uint32_t st = rd(R_STATUS);
        if ((st >> 8) & 1) {
            uint32_t cnt  = rd(R_R_CNT);
            uint32_t info = rd(R_R_INFO);
            uint32_t feat = rd(R_R_FEAT);
            uint32_t thr  = rd(R_R_THR);
            uint8_t tag[16];
            for (int w = 0; w < 4; w++) {
                uint32_t v = rd(R_TAG0 + 4 * w);
                for (int b = 0; b < 4; b++) tag[4 * w + b] = (uint8_t)(v >> (8 * b));
            }
            wr(R_CTRL, 2);

            int s = (info >> 8) & 3;
            char tag_hex[33];
            for (int b = 0; b < 16; b++) sprintf(tag_hex + 2 * b, "%02x", tag[b]);
            char msg[400];
            int len = snprintf(msg, sizeof msg,
                "{\"room\":%u,\"counter\":%u,\"status\":%d,\"mot\":%u,\"br\":%u,"
                "\"tmot\":%u,\"tbr\":%u,\"flags\":%u,\"session\":\"%016llx\",\"tag\":\"%s\"}",
                info & 0xFF, cnt, s, feat & 0xFFFF, feat >> 16, thr & 0xFFFF, thr >> 16,
                (info >> 16) & 0xFF, (unsigned long long)session, tag_hex);
            sendto(sock, msg, len, 0, (struct sockaddr *)&dst, sizeof dst);
            printf("#%-6u %-15s mot %5u br %5u  tag %.8s...\n",
                   cnt, nama[s], feat & 0xFFFF, feat >> 16, tag_hex);
            fflush(stdout);
        }
        if (now_s() - t_info > 10) {
            printf("[info] frame CSI ok %u, salah %u, laporan terlewat %u\n",
                   rd(R_CSI_OK), rd(R_CSI_ERR), rd(R_DROPPED));
            t_info = now_s();
        }
        usleep(1000);
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "pakai: %s run [opsi] | bench file.hex [--sw-only] [--check golden.hex]\n", argv[0]);
        return 1;
    }
    uint32_t off = 0x10000;
    const char *ip = "127.0.0.1", *golden = NULL, *csi = NULL;
    int port = 5005, room = 3, every = 25, t_mot = 250, t_br = 100, sw_only = 0;
    for (int a = 2; a < argc; a++) {
        if (!strcmp(argv[a], "-b") && a + 1 < argc) off = strtoul(argv[++a], NULL, 16);
        else if (!strcmp(argv[a], "-s") && a + 1 < argc) ip = argv[++a];
        else if (!strcmp(argv[a], "-p") && a + 1 < argc) port = atoi(argv[++a]);
        else if (!strcmp(argv[a], "-r") && a + 1 < argc) room = atoi(argv[++a]);
        else if (!strcmp(argv[a], "-e") && a + 1 < argc) every = atoi(argv[++a]);
        else if (!strcmp(argv[a], "-m") && a + 1 < argc) t_mot = atoi(argv[++a]);
        else if (!strcmp(argv[a], "-t") && a + 1 < argc) t_br = atoi(argv[++a]);
        else if (!strcmp(argv[a], "--sw-only")) sw_only = 1;
        else if (!strcmp(argv[a], "--check") && a + 1 < argc) golden = argv[++a];
        else csi = argv[a];
    }
    if (!strcmp(argv[1], "selftest")) {

        uint64_t k[2] = {0x0706050403020100ull, 0x0F0E0D0C0B0A0908ull};
        uint64_t n[2] = {0x1122334455667788ull, ((uint64_t)3 << 32) | 7};
        uint64_t ad[2] = {((uint64_t)74 << 48) | ((uint64_t)1 << 40) | ((uint64_t)7 << 8) | 3,
                          ((uint64_t)1 << 56) | ((uint64_t)100 << 32) | ((uint64_t)250 << 16) | 200};
        uint64_t t[2];
        ascon_tag_sw(k, n, ad, t);
        for (int b = 0; b < 16; b++) printf("%02x", (unsigned)((t[b / 8] >> (8 * (b % 8))) & 0xFF));
        printf("\n");
        return 0;
    }
    if (!strcmp(argv[1], "run")) return cmd_run(off, ip, port, room, every, t_mot, t_br);
    if (!strcmp(argv[1], "bench") && csi) return cmd_bench(csi, sw_only, golden, off, t_mot, t_br);
    fprintf(stderr, "perintah tidak dikenal\n");
    return 1;
}
