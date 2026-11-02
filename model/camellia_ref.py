#!/usr/bin/env python3
"""
camellia_ref.py -- Camellia-128 byte-serial compact core: cycle-accurate reference model

The model reproduces, cycle by cycle, the datapath and FSM defined in
camellia_compact_spec.md, and is checked against a straightforward
RFC 3713-style implementation (golden).

Usage:
  python3 camellia_ref.py selftest           # RFC 3713 vector + random cross-check
  python3 camellia_ref.py gen OUTDIR [N]     # write s1.hex, keyrom.hex, pmask.hex, vectors.hex
  python3 camellia_ref.py trace KEY PT [enc|dec]   # per-cycle trace (hex strings, 32 digits)
"""
import os
import random
import sys

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
S1 = bytes.fromhex(
    "70822cecb327c0e5e4855735ea0cae41"
    "23ef6b934519a521ed0e4f4e1d6592bd"
    "86b8af8f7ceb1fce3e30dc5f5ec50b1a"
    "a6e139cad5475d3dd9015ad651566c4d"
    "8b0d9a66fbccb02d74122b20f0b18499"
    "df4ccbc2347e76056db7a931d11704d7"
    "14583a61de1b111c320f9c165318f222"
    "fe44cfb2c3b57a912408e8a860fc6950"
    "aad0a07da1896297545b1e95e0ff64d2"
    "10c40048a3f775db8a03e6da093fdd94"
    "875c8302cd4a90337367f6f39d7fbfe2"
    "529bd826c837c63b81966f4b13be632e"
    "e979a78c9f6ebc8e29f5f9b62ffdb459"
    "7898066ae74671bad425ab4288a28dfa"
    "7207b955f8eeac0a36492a683c38f1a4"
    "4028d37bbbc943c115e3adf477c7809e"
)
assert len(S1) == 256 and len(set(S1)) == 256

SIGMA = [0xA09E667F3BCC908B, 0xB67AE8584CAA73B2,
         0xC6EF372FE94F82BE, 0x54FF53A5F1D36F1C]
M64, M128 = (1 << 64) - 1, (1 << 128) - 1


def rotl8(x, n):
    n &= 7
    return ((x << n) | (x >> (8 - n))) & 0xFF if n else x


def rotl128(x, n):
    n &= 127
    return ((x << n) | (x >> (128 - n))) & M128 if n else x


def sbox(pos, x):
    """S-box for byte position pos (0 = MSB byte): s1,s2,s3,s4,s2,s3,s4,s1"""
    k = [1, 2, 3, 4, 2, 3, 4, 1][pos]
    if k == 1:
        return S1[x]
    if k == 2:
        return rotl8(S1[x], 1)
    if k == 3:
        return rotl8(S1[x], 7)
    return S1[rotl8(x, 1)]


# P function: output byte i = XOR of z[j] for j in PROW[i]  (0-based, byte 0 = MSB)
PROW = [
    [0, 2, 3, 5, 6, 7],
    [0, 1, 3, 4, 6, 7],
    [0, 1, 2, 4, 5, 7],
    [1, 2, 3, 4, 5, 6],
    [0, 1, 5, 6, 7],
    [1, 2, 4, 6, 7],
    [2, 3, 4, 5, 7],
    [0, 3, 4, 5, 6],
]
# Column mask: input byte j contributes to output byte i when bit (7-i) of PCOL[j] is 1
# (bit7 = output byte 0 = MSB byte of the half)
PCOL = [sum(1 << (7 - i) for i in range(8) if j in PROW[i]) for j in range(8)]

# ---------------------------------------------------------------------------
# Golden (RFC 3713 style) implementation
# ---------------------------------------------------------------------------


def F(x, k):
    x ^= k
    t = [(x >> (56 - 8 * i)) & 0xFF for i in range(8)]
    z = [sbox(i, t[i]) for i in range(8)]
    y = [0] * 8
    for i in range(8):
        for j in PROW[i]:
            y[i] ^= z[j]
    v = 0
    for b in y:
        v = (v << 8) | b
    return v


def rotl32(x, n):
    return ((x << n) | (x >> (32 - n))) & 0xFFFFFFFF


def FL(x, k):
    x1, x2, k1, k2 = x >> 32, x & 0xFFFFFFFF, k >> 32, k & 0xFFFFFFFF
    x2 ^= rotl32(x1 & k1, 1)
    x1 ^= (x2 | k2)
    return (x1 << 32) | x2


def FLINV(y, k):
    y1, y2, k1, k2 = y >> 32, y & 0xFFFFFFFF, k >> 32, k & 0xFFFFFFFF
    y1 ^= (y2 | k2)
    y2 ^= rotl32(y1 & k1, 1)
    return (y1 << 32) | y2


def golden_subkeys(K):
    KL = K
    D1, D2 = KL >> 64, KL & M64
    D2 ^= F(D1, SIGMA[0])
    D1 ^= F(D2, SIGMA[1])
    D1 ^= KL >> 64
    D2 ^= KL & M64
    D2 ^= F(D1, SIGMA[2])
    D1 ^= F(D2, SIGMA[3])
    KA = (D1 << 64) | D2

    def L(v, r): return rotl128(v, r) >> 64
    def R(v, r): return rotl128(v, r) & M64
    sk = dict(
        kw1=L(KL, 0), kw2=R(KL, 0), k1=L(KA, 0), k2=R(KA, 0),
        k3=L(KL, 15), k4=R(KL, 15), k5=L(KA, 15), k6=R(KA, 15),
        ke1=L(KA, 30), ke2=R(KA, 30), k7=L(KL, 45), k8=R(KL, 45),
        k9=L(KA, 45), k10=R(KL, 60), k11=L(KA, 60), k12=R(KA, 60),
        ke3=L(KL, 77), ke4=R(KL, 77), k13=L(KL, 94), k14=R(KL, 94),
        k15=L(KA, 94), k16=R(KA, 94), k17=L(KL, 111), k18=R(KL, 111),
        kw3=L(KA, 111), kw4=R(KA, 111))
    return KA, sk


def golden(K, M, dec=False):
    _, k = golden_subkeys(K)
    if dec:
        k = dict(k)
        for a, b in [("kw1", "kw3"), ("kw2", "kw4"), ("ke1", "ke4"), ("ke2", "ke3")]:
            k[a], k[b] = k[b], k[a]
        for i in range(1, 10):
            k["k%d" % i], k["k%d" % (19 - i)] = k["k%d" % (19 - i)], k["k%d" % i]
    D1, D2 = (M >> 64) ^ k["kw1"], (M & M64) ^ k["kw2"]
    r = 1
    for blk in range(3):
        for _ in range(3):
            D2 ^= F(D1, k["k%d" % r]); r += 1
            D1 ^= F(D2, k["k%d" % r]); r += 1
        if blk < 2:
            D1 = FL(D1, k["ke%d" % (2 * blk + 1)])
            D2 = FLINV(D2, k["ke%d" % (2 * blk + 2)])
    D2 ^= k["kw3"]
    D1 ^= k["kw4"]
    return (D2 << 64) | D1

# ---------------------------------------------------------------------------
# Key ROM  (index = {dec, step[4:0]})  entry = {base[5:0], sh[2:0]}  (9 bit)
#   key RAM map: 0..15 = KL, 16..31 = KA, 32..63 = SIGMA1..4 (8 bytes each)
#   byte j of the selected subkey:
#     a0 = {base[5:4], base[3:0] + j}, a1 = {base[5:4], base[3:0] + j + 1}  (4-bit wrap)
#     kbyte = sh==0 ? M[a0] : (M[a0] << sh | M[a1] >> (8-sh)) & 0xFF
# ---------------------------------------------------------------------------
KL_B, KA_B = 0, 16
#                     enc: (src, rot, half)                dec
ENC_SLOTS = {
    0: ("KL", 0, 0),      # load whitening kw1|kw2 (128-bit)
    1: ("KA", 0, 0), 2: ("KA", 0, 1), 3: ("KL", 15, 0), 4: ("KL", 15, 1),
    5: ("KA", 15, 0), 6: ("KA", 15, 1),
    7: ("KA", 30, 0), 8: ("KA", 30, 1),            # ke1 (FL on D1), ke2 (FLINV on D2)
    9: ("KL", 45, 0), 10: ("KL", 45, 1), 11: ("KA", 45, 0), 12: ("KL", 60, 1),
    13: ("KA", 60, 0), 14: ("KA", 60, 1),
    15: ("KL", 77, 0), 16: ("KL", 77, 1),          # ke3, ke4
    17: ("KL", 94, 0), 18: ("KL", 94, 1), 19: ("KA", 94, 0), 20: ("KA", 94, 1),
    21: ("KL", 111, 0), 22: ("KL", 111, 1),
    23: ("KA", 111, 0),   # output whitening kw3|kw4 (128-bit)
}
# decryption: rounds reversed, FL keys swapped, whitening keys swapped
DEC_MAP = {0: 23, 23: 0, 7: 16, 8: 15, 15: 8, 16: 7}
for _r in range(1, 19):
    _s = _r if _r <= 6 else (_r + 2 if _r <= 12 else _r + 4)
    _rr = 19 - _r
    DEC_MAP[_s] = _rr if _rr <= 6 else (_rr + 2 if _rr <= 12 else _rr + 4)


def slot_entry(src, rot, half):
    base = KL_B if src == "KL" else KA_B
    q, sh = rot // 8, rot % 8
    return ((base | ((q + 8 * half) & 15)) << 3) | sh


def build_keyrom():
    rom = [0] * 64
    for dec in (0, 1):
        for st in range(32):
            if st in ENC_SLOTS:
                src = ENC_SLOTS[DEC_MAP[st] if dec else st]
                rom[dec * 32 + st] = slot_entry(*src)
            elif 24 <= st <= 28:  # key schedule (same for enc/dec)
                rom[dec * 32 + st] = {24: 32 << 3, 25: 40 << 3, 26: slot_entry("KL", 0, 0),
                                      27: 48 << 3, 28: 56 << 3}[st]
    return rom


KEYROM = build_keyrom()

# ---------------------------------------------------------------------------
# Cycle-accurate model of the compact core
# ---------------------------------------------------------------------------
# phases
IDLE, LOAD, FRND, FLA_L, FLB_L, FLB_R, FLA_R, KXOR, KSTORE, OUT = range(10)
PNAME = ["IDLE", "LOAD", "FRND", "FLA_L", "FLB_L", "FLB_R", "FLA_R", "KXOR", "KSTORE", "OUT"]
PLEN = {LOAD: 16, FRND: 8, FLA_L: 5, FLB_L: 4, FLB_R: 4, FLA_R: 5, KXOR: 16, KSTORE: 16, OUT: 16}
OP_KEY, OP_ENC, OP_DEC = 0, 1, 2
# ALU modes
A_XOR, A_XORR, A_ANDC, A_OR, A_PASSX, A_PASSK = range(6)
ANAME = ["XOR", "XORR", "ANDC", "OR", "PASSX", "PASSK"]


class Core:
    def __init__(self):
        self.S = [0] * 16
        self.M = [0] * 64
        for i, s in enumerate(SIGMA):
            for j in range(8):
                self.M[32 + 8 * i + j] = (s >> (56 - 8 * j)) & 0xFF
        self.carry = 0
        self.key_valid = False

    def kbyte(self, ent, kj):
        base, sh = ent >> 3, ent & 7
        a0 = (base & 0x30) | ((base + kj) & 15)
        a1 = (base & 0x30) | ((base + kj + 1) & 15)
        b0, b1 = self.M[a0], self.M[a1]
        return ((b0 << sh) | (b1 >> (8 - sh))) & 0xFF if sh else b0

    def run(self, op, din=None, trace=None):
        """Execute one command. din: list of 16 input bytes. Returns (out bytes, cycles)."""
        dec = 1 if op == OP_DEC else 0
        phase, cnt, step, sdir = LOAD, 0, 0, 0
        out, cycles = [], 0
        while phase != IDLE:
            ent = KEYROM[dec * 32 + step]
            # ---------------- datapath control decode ----------------
            mode, xsrc_din, rsel, kj = A_PASSX, False, 0, 0
            use_sb, pos, lanes, ovw, ramwe, ramwa, ramwd = False, 0, 0, False, False, 0, 0
            carry_en = False
            if phase == LOAD:
                xsrc_din, kj = True, cnt
                mode = A_PASSX if op == OP_KEY else A_XOR
                lanes, ovw = 1 << (15 - cnt), True
                if op == OP_KEY:
                    ramwe, ramwa, ramwd = True, cnt, din[cnt]
            elif phase == FRND:
                pos, kj = cnt, cnt
                rsel = 8 * sdir + cnt
                mode = A_XORR if cnt in (3, 6) else A_XOR
                use_sb = True
                lanes = PCOL[cnt] << (8 * sdir)        # dst = other half
            elif phase in (FLA_L, FLA_R):
                hb = 0 if phase == FLA_L else 8
                kj = 0 if cnt == 0 else 4 - cnt
                rsel = hb + kj
                mode, carry_en = A_ANDC, True
                lanes = 0 if cnt == 0 else 1 << (15 - (rsel ^ 4))
            elif phase in (FLB_L, FLB_R):
                hb = 0 if phase == FLB_L else 8
                kj = 4 + cnt
                rsel = hb + kj
                mode = A_OR
                lanes = 1 << (15 - (rsel ^ 4))
            elif phase == KXOR:
                kj, mode, lanes = cnt, A_PASSK, 1 << (15 - cnt)
            elif phase == KSTORE:
                rsel = cnt
                ramwe, ramwa, ramwd = True, 16 + cnt, self.S[cnt]
            elif phase == OUT:
                rsel, kj, mode = cnt ^ 8, cnt, A_XOR
            # ---------------- combinational datapath ----------------
            x = din[cnt] if xsrc_din else self.S[rsel]
            k = self.kbyte(ent, kj)
            if mode == A_XOR:
                alu = x ^ k
            elif mode == A_XORR:
                alu = rotl8(x ^ k, 1)
            elif mode == A_ANDC:
                t = x & k
                alu = ((t << 1) & 0xFF) | self.carry
            elif mode == A_OR:
                alu = x | k
            elif mode == A_PASSX:
                alu = x
            else:
                alu = k
            if use_sb:
                z = S1[alu]
                p = [1, 2, 3, 4, 2, 3, 4, 1][pos]
                bus = rotl8(z, 1) if p == 2 else (rotl8(z, 7) if p == 3 else z)
            else:
                bus = alu
            if trace is not None:
                trace.append("%-6s cnt=%2d step=%2d dir=%d rsel=%2d k=%02x x=%02x alu=%02x bus=%02x lanes=%04x %s" % (
                    PNAME[phase], cnt, step, sdir, rsel, k, x, alu, bus, lanes,
                    "".join("%02x" % b for b in self.S)))
            if phase == OUT:
                out.append(alu)
            # ---------------- clock edge ----------------
            if carry_en:
                self.carry = (x & k) >> 7
            for ln in range(16):
                if lanes >> (15 - ln) & 1:
                    self.S[ln] = bus if ovw else self.S[ln] ^ bus
            if ramwe:
                self.M[ramwa] = ramwd
            cycles += 1
            # ---------------- FSM ----------------
            if cnt == PLEN[phase] - 1:
                cnt = 0
                if phase == LOAD:
                    phase, step, sdir = FRND, (24 if op == OP_KEY else 1), 0
                elif phase == FRND:
                    sdir ^= 1
                    if step in (6, 14):
                        phase = FLA_L
                    elif step == 22:
                        phase = OUT
                    elif step == 25:
                        phase = KXOR
                    elif step == 28:
                        phase = KSTORE
                    step += 1
                elif phase == FLA_L:
                    phase = FLB_L
                elif phase == FLB_L:
                    phase, step = FLB_R, step + 1
                elif phase == FLB_R:
                    phase = FLA_R
                elif phase == FLA_R:
                    phase, step = FRND, step + 1
                elif phase == KXOR:
                    phase, step = FRND, step + 1
                elif phase == KSTORE:
                    phase = IDLE
                    self.key_valid = True
                elif phase == OUT:
                    phase = IDLE
            else:
                cnt += 1
        return out, cycles


def to_bytes(v):
    return [(v >> (120 - 8 * i)) & 0xFF for i in range(16)]


def from_bytes(b):
    v = 0
    for x in b:
        v = (v << 8) | x
    return v


def core_crypt(K, M, dec=False, core=None):
    c = core or Core()
    _, kc = c.run(OP_KEY, to_bytes(K))
    out, dc = c.run(OP_DEC if dec else OP_ENC, to_bytes(M))
    return from_bytes(out), kc, dc

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def selftest(n=2000):
    K = 0x0123456789abcdeffedcba9876543210
    C = 0x67673138549669730857065648eabe43
    assert golden(K, K) == C, "golden RFC vector"
    assert golden(K, C, dec=True) == K
    c, kc, dc = core_crypt(K, K)
    assert c == C, "core RFC vector: %032x" % c
    p, _, _ = core_crypt(K, C, dec=True)
    assert p == K
    try:
        import warnings
        warnings.simplefilter("ignore")
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        ext = lambda k, m: int.from_bytes(Cipher(algorithms.Camellia(k.to_bytes(16, "big")), modes.ECB())
                                          .encryptor().update(m.to_bytes(16, "big")), "big")
    except Exception:
        ext = None
    rnd = random.Random(1)
    for _ in range(n):
        k, m = rnd.getrandbits(128), rnd.getrandbits(128)
        g = golden(k, m)
        if ext:
            assert ext(k, m) == g
        core = Core()
        c, _, _ = core_crypt(k, m, core=core)
        assert c == g
        _, cyc = core.run(OP_DEC, to_bytes(c))
        assert from_bytes(_) == m
    print("selftest OK: RFC3713 vector, %d random enc/dec%s; key=%d cycles, enc/dec=%d cycles" % (
        n, " (cross-checked with OpenSSL)" if ext else "", kc, dc))


def gen(outdir, n=200):
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "s1.hex"), "w") as f:
        f.write("\n".join("%02x" % b for b in S1) + "\n")
    with open(os.path.join(outdir, "keyrom.hex"), "w") as f:
        f.write("\n".join("%03x" % e for e in KEYROM) + "\n")
    with open(os.path.join(outdir, "pmask.hex"), "w") as f:
        f.write("\n".join("%02x" % e for e in PCOL) + "\n")
    rnd = random.Random(2026)
    vec = [(0x0123456789abcdeffedcba9876543210, 0x0123456789abcdeffedcba9876543210)]
    vec += [(0, 0), (M128, M128)]
    vec += [(rnd.getrandbits(128), rnd.getrandbits(128)) for _ in range(n)]
    with open(os.path.join(outdir, "vectors.hex"), "w") as f:
        for k, m in vec:
            f.write("%032x %032x %032x\n" % (k, m, golden(k, m)))
    print("wrote s1.hex keyrom.hex pmask.hex vectors.hex (%d vectors) to %s" % (len(vec), outdir))


def main():
    a = sys.argv[1:]
    if not a or a[0] == "selftest":
        selftest()
    elif a[0] == "gen":
        gen(a[1], int(a[2]) if len(a) > 2 else 200)
    elif a[0] == "trace":
        k, m = int(a[1], 16), int(a[2], 16)
        dec = len(a) > 3 and a[3] == "dec"
        c, t = Core(), []
        c.run(OP_KEY, to_bytes(k), trace=t)
        out, _ = c.run(OP_DEC if dec else OP_ENC, to_bytes(m), trace=t)
        print("\n".join(t))
        print("RESULT %032x" % from_bytes(out))
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
