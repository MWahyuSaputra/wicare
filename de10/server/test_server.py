import json, socket, sys, time
import wicare_ascon as A

KEY = bytes.fromhex(open(sys.argv[1] if len(sys.argv) > 1 else "key.hex").read().strip())
S = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
SESSION = 0xA1B2C3D4E5F60718

def send(cnt, st, mot=40, br=180, tmot=250, tbr=100, flags=0, key=KEY, session=SESSION, room=3):
    tag = A.report_tag(key, session, room, cnt, st, mot, br, tmot, tbr, flags)
    m = dict(room=room, counter=cnt, status=st, mot=mot, br=br, tmot=tmot, tbr=tbr,
             flags=flags, session=f"{session:016x}", tag=tag.hex())
    S.sendto(json.dumps(m).encode(), ("127.0.0.1", 5005))
    time.sleep(0.05)
    return m

print("1. laporan sah: kosong, lalu orang diam");  send(0, 0); send(1, 1)
print("2. replay laporan #0 (kosong)");             send(0, 0)
print("3. tag dipalsukan (kunci salah)");           send(2, 0, key=bytes(16))
m = send(3, 1)
print("4. laporan diubah di jalan (status 1 -> 0)")
m["status"] = 0; m["counter"] = 4
S.sendto(json.dumps(m).encode(), ("127.0.0.1", 5005)); time.sleep(0.05)
print("5. ambang dinaikkan diam-diam");             send(5, 0, tmot=9999)
print("6. CSI disuapkan HPS (flag benchmark)");    send(6, 0, flags=1)
print("7. laporan sah lagi");                       send(7, 2)
print("8. diam 4 detik (gateway mati)");            time.sleep(4)
