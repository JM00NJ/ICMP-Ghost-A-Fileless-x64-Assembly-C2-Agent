<div align="center">

```
 ________  ___  ___  ________  ________  _________       ________  ________   
|\   ____\|\  \|\  \|\   __  \|\   ____\|\___   ___\    |\   ____\|\_____  \  
\ \  \___| \ \  \\\  \ \  \|\  \ \  \___|\|___ \  \_|    \ \  \___|\|____|\  \ 
 \ \  \  __ \ \   __  \ \  \\\  \ \_____  \   \ \  \      \ \  \     ____\_\  \
  \ \  \|\  \ \  \ \  \ \  \\\  \|____|\  \   \ \  \      \ \  \___|\____ \  \
   \ \_______\ \__\ \__\ \_______\____\_\  \   \ \__\      \ \______\\_________\
    \|_______|\|__|\|__|\|_______|\_________\   \|__|       \|______\|_________|
                                 \|_________|                                   
```

> Fileless, pure x64 Assembly C2 implant utilizing a Dual-Channel (ICMP / DNS) architecture. Zero libc. Zero disk. Invisible to standard EDR hooks.

---
![Architecture](https://img.shields.io/badge/Architecture-x86__64-red.svg)
![Language](https://img.shields.io/badge/Language-Pure%20Assembly-green.svg)
![Protocol](https://img.shields.io/badge/Protocol-ICMP-blue.svg)
![Protocol](https://img.shields.io/badge/Protocol-DNS-blue.svg)
![OS](https://img.shields.io/badge/OS-Linux-orange.svg)
![Version](https://img.shields.io/badge/Version-3.6.2-purple.svg)
![Suricata](https://img.shields.io/badge/Suricata%20v8.0.3-Bypassed-brightgreen)

# Ghost-C2

## Overview

Ghost-C2 is a command-and-control framework written entirely in pure x64 Linux Assembly with no libc dependencies. Every operation goes through direct syscalls. There are no import tables, no dynamic linker artifacts, and no disk writes.

Originally built as a raw ICMP stealth channel, version 3.6.2 introduces a **Dual-Channel Protocol Pivoting** architecture. Operators can seamlessly switch the implant's communication channel between silent ICMP Raw Sockets and evasive DNS UDP Tunneling on the fly. The implant lives exclusively in RAM, injected into a running system process via a custom ptrace-based loader.

This project was built to explore how far user-space stealth and network state synchronization can go without touching the kernel.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      OPERATOR MACHINE                       │
│                                                             │
│   ┌──────────────┐                                          │
│   │  client.asm  │  ← Terminal UI: Prompt IP/Domain + Cmd   │
│   │  (Operator   │    Encrypts payload with Rolling XOR     │
│   │   Console)   │    State Sync: ICMP mode / DNS mode      │
│   └──────┬───────┘                                          │
│          │                                                  │
└──────────┼──────────────────────────────────────────────────┘
           │  Channel 1: Raw ICMP (Stateless, Port-less)
           │  Channel 2: DNS UDP Port 53 (Asymmetric)
┌──────────┼──────────────────────────────────────────────────┐
│          │             TARGET MACHINE                       │
│          ▼                                                  │
│   ┌──────────────┐     ┌─────────────────────────────────┐  │
│   │  loader.asm  │────▶│         sniff.asm (PIC)         │  │
│   │  (Phantom    │     │         Lives in RAM only       │  │
│   │   Loader)    │     │         inside host process     │  │
│   └──────────────┘     └────────────────┬────────────────┘  │
│                                         │                   │
│   1. Scans /proc for target PID         │ Listens ICMP/DNS  │
│   2. ptrace ATTACH                      │ Validates Auth    │
│   3. Force remote mmap (RW)             │ Decrypts command  │
│   4. Inject PIC shellcode               │ fork+execve       │
│   5. mprotect → RX                      │ memfd_create      │
│   6. Redirect RIP → shellcode           │ Compress(DPCM-RLE)│
│   7. ptrace DETACH → exits              │ Encrypt & Frag.   │
│                                         │ Sends Reply       │
└─────────────────────────────────────────┼───────────────────┘
                                          │  Encrypted Traffic
                                          ▼
                                   [ client.asm ]
                                   Receives & Validates
                                   Decrypts Payload
                                   Decompresses (Hybrid)
                                   Reassembles & Prints
```

---

## Components

### `client.asm` — Operator Console
The attacker-side terminal. Handles UI, dynamic memory management, and target state synchronization. Can dispatch packets as either ICMP Echo Requests or DNS TXT queries. Listens for fragmented replies, prevents buffer overflows, and reconstructs the output. Features an "Active Target Reconnection" module to rescue orphaned sessions.

### `sniff.asm` — PIC Implant Agent
The implant running on the target. Compiled as a raw binary (position-independent, no ELF headers) so it can be injected into arbitrary memory addresses. It dynamically updates its internal VTable to switch between ICMP sniffing and UDP DNS binding based on operator pivot commands.

### `Phantom_Loader/loader.asm` — Injection Engine
The delivery mechanism. Scans `/proc`, finds a target process by comm name, and injects the PIC shellcode into it using a multi-stage ptrace state machine. Exits cleanly after injection — leaves no trace.

---

## Stealth & Evasion Techniques

### Dual-Channel Protocol Pivoting (ICMP ↔ DNS)
Ghost-C2 v3.6.2 allows the operator to hot-swap the network protocol without losing the agent. By sending specific pivot commands, the VTables in both the Master and the Agent are dynamically overwritten:

- **`!D` (Pivot to DNS):** Both nodes close ICMP sockets and initialize UDP Port 53 communication. Ideal for bypassing strict Layer 3 filtering by blending into corporate DNS traffic.
- **`!I` (Pivot to ICMP):** The Agent closes UDP sockets, kills port bindings, and drops back into silent Raw Socket sniffing. Perfect for "Phantom" stealth mode.

### DPCM-RLE Hybrid x64 Compressor
Ghost-C2's data transmission engine utilizes a hybrid compression and encoding layer heavily optimized in x86-64 Assembly.

- **DPCM** (Differential Pulse Code Modulation): Calculates and sends the mathematical difference (Delta) between a reference character and subsequent ones, lowering data entropy.
- **RLE** (Run-Length Encoding): Packs consecutive spaces and repeating blocks at the bit level.
- **Result:** Reduces overall data payload by 40% to 55%, minimizing network footprint and the number of injected packets.

### ICMP Protocol Mimicry
Every outgoing ICMP packet is structured to be indistinguishable from a standard Linux `ping`:
- Dynamic RDTSC timestamps mimic `struct timeval`.
- Exact Linux `iputils` padding (`0x10` to `0x1F`) bypasses basic heuristic firewalls.

### Rolling XOR Cipher
Both directions are encrypted with a progressively shifting QWORD key. This keeps Shannon entropy low (unlike AES, which scores ~8.0 and triggers DPI anomalies). Rolling XOR produces entropy that looks like naturally noisy data. No cryptographic constants, no S-boxes, nothing for YARA to match.

### Asymmetric Authentication
The implant ignores all ICMP packets where `ID + SEQ ≠ 45,000`. The implant replies with packets where `ID + SEQ = 55,000`. This prevents OS echo confusion and filters out internet scanners or honeypots.

### Fileless Execution via `memfd_create`
Command output never touches disk. The shell output is captured via an anonymous RAM file (`memfd_create`), named `[shm]` to blend into legitimate shared memory mappings in `/proc/PID/fd`.

### W^X Memory Injection (Phantom Loader)
Defeats modern kernel mitigations that forbid RWX memory. The loader uses a two-phase approach (`Remote mmap` with RW → Inject → `Remote mprotect` with RX). No page is ever simultaneously W and X.

### Libc-Free Syscall Obfuscation
All syscall numbers are split across two instructions to defeat static analysis and simple grep-based scanners.

---

## Weaponization: Configuring & Building the Agent

To maintain strict OPSEC, the Ghost-C2 agent (`sniff.asm`) does not use external configurations. You must define your Master C2 IP, Port, and Decoy DNS Domain directly inside the assembly code before compiling and injecting.

### Step 1: Configure OPSEC Variables
Open `sniff.asm` and scroll to the very bottom of the `.text` segment. *(Note: Because the agent is strictly Position Independent Code (PIC), there is no `.data` segment. All configuration variables are stored inline).*

Modify the following values to match your Master Server:
- **IP Address:** Change `db 127, 0, 0, 1` to your Master's IP.
- **UDP Port:** Change `dw 0xB414` (Port 5300) to your desired port in Network Byte Order (e.g., `0x3500` for Port 53).
- **Decoy Domain:** Change `fake_domain` (e.g., `ghost.com`) to match the authoritative domain configured on your Master.

### Step 2: Assemble to Raw Shellcode

```bash
nasm -f bin sniff.asm -o shellcode.bin
```

### Step 3: Format the Shellcode

```bash
python3 -c "data = open('shellcode.bin', 'rb').read(); lines = ['\tdb ' + ', '.join(f'0x{b:02x}' for b in data[i:i+12]) for i in range(0, len(data), 12)]; open('c2_payload.txt', 'w').write('\n'.join(lines))"
```

### Step 4: Encrypt the Payload (Rolling XOR)
1. Copy the contents of the generated `c2_payload.txt`.
2. Open `xor.py` and replace the `raw_asm` variable's contents with your copied shellcode.
3. Run `python3 xor.py` and copy the encrypted output.

### Step 5: Inject into the Phantom Loader
1. Open `loader.asm`.
2. Locate the `c2_payload:` label.
3. Delete the existing placeholder and paste your encrypted shellcode directly under the label.
4. *(Optional: Change the target injection process by modifying `target db "cron", 10`).*

### Step 6: Compile the Final Loader

```bash
nasm -f elf64 loader.asm -o loader.o
ld loader.o -o loader
```

Execute on the target machine with root privileges (`sudo ./loader`). The agent is now running entirely fileless.

---

## Configuring the Operator Console (client.asm)
Before compiling the Master Console, you must ensure its listener and target profiles align with your Agent's configuration. Open client.asm and navigate to the section .data area.

### Step 1: Configure Listener Port
Locate master_bind_addr. This is where the Master listens for incoming DNS beacons.

UDP Port: Change dw 0xB414 to match the port your Agent is sending to.

> **Note:** This must be in Network Byte Order. For Port 53, use 0x3500.

### Step 2: Configure Pivot/Reconnect Port
Locate target_addr. This port is used when you perform a DNS Pivot (!D) or use the Reconnect module.

Port Alignment: Change dw 0xB414 to match the UDP port the Agent is listening on. If these ports do not match, the (Deadlock) will occur as the Master will be shouting into the wrong void.

### Step 3: Build the Console
Once configured, assemble and link the Master:

```bash
nasm -f elf64 client.asm -o client.o
ld client.o -o client
```

### 💡 OPSEC Tip for Users
Protip: Always keep a "Profile Sheet" for your operation. If you change the port to 0x3500 (Port 53) in sniff.asm, you MUST update both master_bind_addr and target_addr in client.asm before the operation begins.

> **Note:** The Operator Console requires root privileges to bind raw sockets and UDP port 53.

## ⚠️ CRITICAL: Operational State Synchronization
To ensure persistent access and prevent session loss, always pivot the Agent back to ICMP Mode (!I) before terminating your Master Console session.

The Logic: ICMP is Ghost-C2's "Golden Channel"—it is stateless, passive, and always reachable via the Target IP.

The Risk: DNS mode relies on dynamic UDP port synchronization. If the Master Console is closed while in DNS mode, the Agent remains "trapped" in a UDP listening state. Re-establishing connection would require knowing the Agent's specific ephemeral port, which is lost upon Master restart.

## Rule of Thumb
1. !I (Switch to ICMP)
2. Verify Command Prompt
3. Ctrl+C (Exit Master)

---

## Empirical Results

Tested in a controlled lab environment against active traffic inspection:

| Test | Result |
|---|---|
| Suricata v8.0.3 (Emerging Threats ruleset) | ✅ Bypassed |
| Suricata v8.0.3 (Custom ICMP payload rules) | ✅ Bypassed |
| DigitalOcean FRA1 gateway | ✅ 100% exfiltration success |
| Alerts generated during ~25KB exfiltration | 0 |

---

## Syscall Reference

Ghost-C2 interacts directly with the Linux kernel:

| Syscall | Number | Usage |
|---|---|---|
| `sys_socket` | 41 | Raw ICMP / UDP socket creation |
| `sys_recvfrom` | 45 | Passive ICMP/UDP packet capture |
| `sys_sendto` | 44 | ICMP/UDP reply transmission |
| `sys_bind` | 49 | UDP DNS Port binding |
| `sys_memfd_create` | 319 | Anonymous RAM file for output |
| `sys_dup2` | 33 | stdout/stderr redirection |
| `sys_execve` | 59 | Shell command execution |
| `sys_fork` | 57 | Process isolation |
| `sys_ptrace` | 101 | Process injection + anti-debug |
| `sys_getdents64` | 217 | /proc directory parsing |
| `sys_mmap` | 9 | Remote memory allocation |
| `sys_mprotect` | 10 | W^X permission switch |

---

## Roadmap

### v4.0 — DNS RFC Compliance & Asynchronous Beaconing
- **RFC Headers:** Currently, the DNS tunneling module operates on raw Hex/Base32 over UDP, which triggers "Malformed Packet" warnings in Wireshark. v4.0 will wrap payloads in fully compliant RFC 1035 headers (Transaction IDs, QTYPE, etc.) to bypass strict IDS/IPS protocol anomaly detection.
- **Asynchronous Jitter / Nonce:** To successfully route payloads through Public ISP caches to the C2 Authoritative Name Server, a unique randomized nonce/jitter will be prepended to every subdomain query to prevent DNS caching drops.

### v4.x — MAC Bypass Research
Research into bypassing AppArmor and SELinux confined processes using ROP-based execution (Living off the Land in memory) and dynamic ASLR defeat to eliminate `mprotect` dependencies.

---

## Why No Interactive TTY?

The absence of a PTY is an architectural decision, not a limitation:

- **Protocol integrity:** ICMP and DNS are stateless/asymmetric. Emulating TCP-like ordered delivery for a TTY stream would bloat the codebase and destroy the lightweight design.
- **Volumetric stealth:** An interactive shell generates traffic for every keystroke, creating a detectable frequency spike.
- **EDR surface:** Allocating a PTY requires `/dev/ptmx` and `ioctl` calls that EDRs heavily monitor.

Ghost-C2 is a hyper-stealth command execution and exfiltration implant. Interactivity trades invisibility for convenience — this project chose invisibility.

---

## Contributing

By design, Pull Requests and Forks are strictly ignored. The architecture of this project is maintained directly by the author. If you find a bug, logic flaw, or have a feature suggestion, please open an Issue. Keep it objective and technical.

---

## Resources

- **Blog / Technical Writeup:** [netacoding.com/posts/icmp-ghost](https://netacoding.com/posts/icmp-ghost)
- **Author:** [github.com/JM00NJ](https://github.com/JM00NJ)
- **Related Resource:** [netacoding.com/posts/compressdpcm-rle](https://netacoding.com/posts/compressdpcm-rle)

---

## 💖 Support the Project

Ghost-C2 is built with passion, sweat, and pure x64 Assembly. If this project helped you understand low-level evasion, protocol mimicry, or just made your red teaming operations smoother, consider supporting the development!

👉 [Become a Sponsor on GitHub](#)

---

## ⚖️ Disclaimer & License (AGPL-3.0)

Ghost-C2 is developed strictly for **educational purposes**, reverse engineering, and authorized cybersecurity research.

As of version 3.6.1 and onwards, this project is licensed under the **GNU Affero General Public License v3.0 (AGPLv3)**. Any entity interacting with or modifying this software over a network must disclose their complete source code as mandated by the license. Commercial exploitation or integration into proprietary/closed-source platforms is strictly prohibited.

*Copyright (c) 2026 JM00NJ (commSync). All Rights Reserved.*

> The author is not responsible for any illegal use or damage caused by this tool. Use it at your own risk.
