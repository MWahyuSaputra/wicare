import math
import random

FS = 50
SEG_S = 30
random.seed(7)

def scenario(kind, n):
    out = []
    breath_f = 0.25
    mov = 0.0
    for k in range(n):
        t = k / FS
        a = 60.0 + 0.8 * math.sin(2 * math.pi * 0.01 * t)
        a += random.gauss(0, 0.6)
        if kind >= 1:
            a += 3.0 * math.sin(2 * math.pi * breath_f * t)
        if kind == 2:
            mov = 0.7 * mov + random.gauss(0, 9.0)
            a += mov
        phi = 0.6
        i = max(-127, min(127, round(a * math.cos(phi))))
        q = max(-127, min(127, round(a * math.sin(phi))))
        out.append((i, q, kind))
    return out

samples = []
for kind in (0, 1, 2, 0):
    samples += scenario(kind, SEG_S * FS)

T_MOT = 250
T_BR = 100
HOLD = 25

s_fast = s_slow = 0
mot = br = 0
cand_prev = 0
cnt = 0
status = 0
first = True
golden = []
for i, q, _ in samples:
    pwr = i * i + q * q
    if first:
        s_fast = s_slow = pwr << 8
        first = False
    s_fast += ((pwr << 8) - s_fast) >> 3
    s_slow += ((pwr << 8) - s_slow) >> 8
    y_fast = s_fast >> 8
    y_slow = s_slow >> 8
    hp = pwr - y_fast
    bp = y_fast - y_slow
    mot += (abs(hp) - mot) >> 4
    br += (abs(bp) - br) >> 6
    cand = 2 if mot > T_MOT else (1 if br > T_BR else 0)
    if cand == cand_prev:
        if cnt < HOLD:
            cnt += 1
    else:
        cnt = 0
    cand_prev = cand
    if cnt == HOLD:
        status = cand
    golden.append(status)

with open("csi_data.hex", "w") as f:
    for i, q, _ in samples:
        f.write(f"{i & 0xFF:02x}{q & 0xFF:02x}\n")
with open("golden_status.hex", "w") as f:
    for s in golden:
        f.write(f"{s:x}\n")
with open("label.hex", "w") as f:
    for *_, k in samples:
        f.write(f"{k:x}\n")

names = ["kosong", "diam", "bergerak", "kosong"]
n = SEG_S * FS
for s, name in enumerate(names):
    seg = range(s * n + 5 * FS, (s + 1) * n)
    ok = sum(golden[k] == samples[k][2] for k in seg)
    print(f"Segmen {s} ({name:8s}): akurasi {100 * ok / len(seg):5.1f}%")
print(f"Total paket: {len(samples)}")
