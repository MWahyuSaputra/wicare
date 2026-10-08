import sys, time, threading
import serial

port = sys.argv[1] if len(sys.argv) > 1 else "COM5"
ser = serial.Serial(port, 115200, timeout=0.1)

def baca():
    buf = b""
    while True:
        buf += ser.read(64)
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            print("FPGA:", line.decode(errors="replace").strip())

threading.Thread(target=baca, daemon=True).start()

frames = []
for line in open("csi_data.hex"):
    v = int(line.strip(), 16)
    i, q = v >> 8, v & 0xFF
    frames.append(bytes([0xAA, 0x55, i, q, i ^ q]))

print(f"Mengirim {len(frames)} frame pada 50 Hz (~{len(frames)//50} detik)...")
t0 = time.perf_counter()
for k, f in enumerate(frames):
    ser.write(f)
    while time.perf_counter() < t0 + (k + 1) / 50:
        time.sleep(0.001)
time.sleep(1)
print("Selesai.")
