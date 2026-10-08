import os, sys
import serial

port = sys.argv[1] if len(sys.argv) > 1 else "COM6"
if "--reuse" in sys.argv:
    key = bytes.fromhex(open("key.hex").read().strip())
else:
    key = os.urandom(16)
    open("key.hex", "w").write(key.hex())
    print("Kunci baru disimpan di key.hex")

with serial.Serial(port, 115200) as s:
    s.write(b"K" + key)
    s.flush()
print("Kunci terkirim. LED[3] di board harus menyala (kunci siap).")
