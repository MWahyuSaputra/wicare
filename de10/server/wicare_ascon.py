M64 = (1 << 64) - 1
IV = 0x00001000808C0001
RC = [0xF0, 0xE1, 0xD2, 0xC3, 0xB4, 0xA5, 0x96, 0x87, 0x78, 0x69, 0x5A, 0x4B]

def rotr(x, n):
    return ((x >> n) | (x << (64 - n))) & M64

def perm(S, rounds):
    for r in RC[12 - rounds:]:
        x0, x1, x2, x3, x4 = S
        x2 ^= r
        x0 ^= x4; x4 ^= x3; x2 ^= x1
        t0 = ~x0 & x1; t1 = ~x1 & x2; t2 = ~x2 & x3; t3 = ~x3 & x4; t4 = ~x4 & x0
        x0 ^= t1; x1 ^= t2; x2 ^= t3; x3 ^= t4; x4 ^= t0
        x1 ^= x0; x0 ^= x4; x3 ^= x2; x2 = ~x2
        x0, x1, x2, x3, x4 = [v & M64 for v in (x0, x1, x2, x3, x4)]
        x0 ^= rotr(x0, 19) ^ rotr(x0, 28)
        x1 ^= rotr(x1, 61) ^ rotr(x1, 39)
        x2 ^= rotr(x2, 1) ^ rotr(x2, 6)
        x3 ^= rotr(x3, 10) ^ rotr(x3, 17)
        x4 ^= rotr(x4, 7) ^ rotr(x4, 41)
        S[:] = [x0, x1, x2, x3, x4]

def le(b):
    return int.from_bytes(b, "little")

def tag(key: bytes, nonce: bytes, ad: bytes) -> bytes:
    assert len(key) == 16 and len(nonce) == 16 and 0 < len(ad) <= 15
    k0, k1 = le(key[:8]), le(key[8:])
    S = [IV, k0, k1, le(nonce[:8]), le(nonce[8:])]
    perm(S, 12)
    S[3] ^= k0; S[4] ^= k1
    pad = ad + b"\x01" + bytes(15 - len(ad))
    S[0] ^= le(pad[:8]); S[1] ^= le(pad[8:])
    perm(S, 8)
    S[4] ^= 1 << 63
    S[0] ^= 0x01
    S[2] ^= k0; S[3] ^= k1
    perm(S, 12)
    return ((S[3] ^ k0).to_bytes(8, "little") + (S[4] ^ k1).to_bytes(8, "little"))

def report_ad(room, counter, status, mot16, br16, tmot, tbr, flags) -> bytes:
    return (bytes([room]) + counter.to_bytes(4, "little") + bytes([status])
            + mot16.to_bytes(2, "little") + br16.to_bytes(2, "little")
            + tmot.to_bytes(2, "little") + tbr.to_bytes(2, "little") + bytes([flags]))

def report_nonce(session, counter, room) -> bytes:
    return session.to_bytes(8, "little") + counter.to_bytes(4, "little") + bytes([room, 0, 0, 0])

def report_tag(key, session, room, counter, status, mot16, br16, tmot, tbr, flags) -> bytes:
    return tag(key, report_nonce(session, counter, room),
               report_ad(room, counter, status, mot16, br16, tmot, tbr, flags))
