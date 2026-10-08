import sys
sys.path.insert(0, "../server")
import wicare_ascon as A
import golden

KEY = bytes(range(16))
SESSION = 0x1122334455667788
EVERY = 25

iq = golden.load_hex()
gold = golden.run(iq)
rows = [l.split() for l in open("reports.txt") if l.strip()]
err = 0
for n, r in enumerate(rows):
    cnt, room, status, flags, mot, br, tmot, tbr = map(int, r[:8])
    tag_hex = r[8]
    calc = A.report_tag(KEY, SESSION, room, cnt, status, mot, br, tmot, tbr, flags)
    got = bytes.fromhex(tag_hex)[::-1]
    if calc != got:
        err += 1; print("TAG SALAH laporan", n)
    if cnt != n:
        err += 1; print("COUNTER loncat", n, cnt)
    seg_idx = n if n < 240 else n - 240
    pk = seg_idx * EVERY + EVERY - 1
    gs, gm, gb = gold[pk]
    exp = (gs, min(gm, 65535), min(gb, 65535), 0 if n < 240 else 1)
    if (status, mot, br, flags) != exp:
        err += 1; print("ISI beda laporan", n, (status, mot, br, flags), exp)

print(f"{len(rows)} laporan diperiksa: tag, counter, status, fitur, flag sumber")
print("HASIL: PASS" if err == 0 and len(rows) == 260 else f"HASIL: FAIL ({err} kesalahan)")
