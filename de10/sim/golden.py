def run(iq, t_mot=250, t_br=100, hold=25):
    s_fast = s_slow = mot = br = 0
    cand_prev = cnt = status = 0
    first = True
    out = []
    for i, q in iq:
        pwr = i * i + q * q
        if first:
            s_fast = s_slow = pwr << 8
            first = False
        s_fast += ((pwr << 8) - s_fast) >> 3
        s_slow += ((pwr << 8) - s_slow) >> 8
        yf, ys = s_fast >> 8, s_slow >> 8
        hp, bp = pwr - yf, yf - ys
        mot += (abs(hp) - mot) >> 4
        br += (abs(bp) - br) >> 6
        cand = 2 if mot > t_mot else (1 if br > t_br else 0)
        cnt = 0 if cand != cand_prev else min(cnt + 1, hold)
        cand_prev = cand
        if cnt == hold:
            status = cand
        out.append((status, mot, br))
    return out

def load_hex(path="csi_data.hex"):
    iq = []
    for line in open(path):
        v = int(line.strip(), 16)
        i, q = v >> 8, v & 0xFF
        iq.append((i - 256 if i > 127 else i, q - 256 if q > 127 else q))
    return iq
