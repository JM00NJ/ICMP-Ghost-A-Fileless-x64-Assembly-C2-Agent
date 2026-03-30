# 👻 Ghost-C2: Fileless x64 Assembly ICMP C2 (v3.0.0)

![Suricata](https://img.shields.io/badge/Suricata%20v8.0.3-Bypassed-brightgreen?style=for-the-badge)

![Architecture](https://img.shields.io/badge/Architecture-x86__64-red.svg)
![Language](https://img.shields.io/badge/Language-Pure%20Assembly-green.svg)
![Protocol](https://img.shields.io/badge/Protocol-ICMP-blue.svg)
![OS](https://img.shields.io/badge/OS-Linux-orange.svg)

**Ghost-C2 is a fileless, server-side implant written in pure x64 Assembly. It leverages raw ICMP sockets for stealthy command and control, acting as a passive, stateless listener that only responds to a specific Magic Sequence.

## Star vs. Clone
I see you're interested in the code! If you're one of the many people cloning this repo, consider dropping a Star as well. It helps the project stay visible and reach more low-level enthusiasts

---

 ## 🚀 The "Stealth" Update (v3.0.0) - What's New?
With the latest release, Ghost-C2 has reached a new level of operational security, effectively defeating Deep Packet Inspection (DPI) and behavioral heuristics:

[DONE] Protocol Mimicry (Padding): Encapsulates encrypted payloads within standard Linux ping data patterns. It mimics legitimate diagnostic traffic by including a dynamic timestamp (RDTSC) and a 24-byte sequence padding (0x10-0x1F).

[DONE] Traffic Shaping (Jitter): Implements randomized transmission intervals (100-300ms jitter) using rdtsc to disrupt periodic beaconing detection and simulate human-like network activity.

[DONE] Data Fragmentation (Chunking): Automatically fragments large command outputs into small chunks, ensuring the total ICMP packet stays within standard diagnostic boundaries (64-byte or 88-byte profiles) to bypass MTU limits and avoid anomaly detection.

[DONE] Bi-directional Stream Obfuscation (Rolling XOR): Both ICMP Echo Request and Reply streams are protected by a Symmetric Rolling XOR Cipher. Each byte within a single packet is encrypted with a progressively shifting key (dl += 0x07), ensuring that static byte-pattern signatures are broken. This ensures high payload entropy and prevents "Asymmetric Encryption Disparity," making the traffic appear as non-patterned noise to Deep Packet Inspection (DPI) engines.

[DONE] Dynamic Process Masquerading: Renaming the process at runtime (e.g., to [kworker] or systemd).

[DONE] Anti-Debugging & Anti-VM: Adding ptrace checks and environmental artifact detection. 

## 🎯 Target Environments & Operational Viability (v3.0)
Ghost-C2 v3.0 is optimized for high-stealth operations in environments protected by active Deep Packet Inspection (DPI) and behavioral monitoring. By mimicking standard Linux ping signatures and disrupting beaconing patterns, it effectively bypasses most automated IDS/IPS signature filters.

## 🚀 Empirical Success Verification (v3.0.0)
Ghost-C2 has been rigorously tested in a controlled environment against modern traffic analysis engines.

Suricata v8.0.3 (Latest Release) Bypass: Confirmed. The implant successfully evaded detection under:

Standard Rule Sets: Emerging Threats (ET) Open signatures.

Custom Heuristics: Manually defined rules targeting high-frequency ICMP traffic and non-standard payload patterns.

DigitalOcean Cloud (FRA1): %100 Success rate in exfiltrating system data (cat /etc/services, ps aux) through a hardened gateway.

Zero-Alert Policy: During the transfer of ~25KB of system metadata, zero (0) alerts were triggered in fast.log.

"Tested against custom 'Protocol Violation' and 'ICMP Payload Anomaly' rules."

Ideal Deployment Scenarios:

Stealth Persistence: Maintaining access on compromised Linux web servers (WordPress, Magento, etc.) without leaving disk artifacts.

Evasion Testing: Evaluating the effectiveness of SOC/IDS teams against non-standard, low-level protocol tunneling.

Post-Exploitation: Exfiltrating sensitive command outputs from environments where TCP/UDP traffic is strictly proxied but ICMP is allowed.

The v3.0 release has been operationally verified to bypass active Suricata deployments. The XOR stream sync ensures that even large file exfiltrations remain below the noise floor of standard network monitoring.

---
## 💻 Low-Level Implementation (Syscall Inventory)
This implant operates without any external libraries (libc-free), interacting directly with the Linux Kernel via:

sys_socket (41) & sys_recvfrom (45): For raw ICMP layer interaction.

sys_memfd_create (319): For fileless command output buffering in RAM.

sys_dup2 (33) & sys_execve (59): For I/O redirection and shell execution.

sys_nanosleep (35): For implementing randomized jitter.

sys_ptrace (101) & sys_prctl(157) : For Anti-Debug & Anti-Dump - Masquerading

## 🛠 Architecture Overview
Stateless Evasion: Operates purely on raw ICMP sockets, bypassing stateful firewall tracking common in TCP/UDP connections.

Fileless Execution: Uses sys_memfd_create to capture command output in RAM, ensuring no disk artifacts are left behind.

Full I/O Redirection: Captures both STDOUT and STDERR, ensuring full visibility even during command failures.

Asymmetric Signature-less Trigger: The C2 architecture eliminates all static signatures. It employs a polymorphic authentication mechanism where the agent validates commands based on an asymmetric mathematical sum. By emulating standard Linux/Windows ping patterns (High-entropy IDs and PID-range sequences), it makes C2 traffic indistinguishable from normal ICMP activity, rendering static YARA and Suricata rules ineffective.
   
   INFO:    Asymmetric Key Exchange: Master sends commands with $Key = 45000$, and Agent replies with $Key = 55000$ to prevent local network echo interference and OS auto-reply confusion.

---

## 🗺 Roadmap & Future Enhancements

## 🚀 Upcoming in v4.0: Project "Phantom Loader" (In-Memory Execution)

The next major update will introduce a state-of-the-art **Reflective ELF Injector**, completely written in raw x64 Assembly. Ghost-C2 will transition from a standalone executable to a fileless, memory-only threat.

**Technical Roadmap:**
* [ ] **Dynamic Target Acquisition:** Automated parsing of the `/proc` directory via `getdents64` and `openat` syscalls to dynamically locate target processes (e.g., `systemd-networkd`) without relying on libc.
* [ ] **Process Subversion (`ptrace`):** Attaching to the target process and halting execution via `PTRACE_ATTACH`.
* [ ] **Remote Memory Allocation:** Forcing the target process to execute `sys_mmap` via a custom injected stub to allocate hidden `RX/RW` memory regions.
* [ ] **Reflective ELF Mapping:** Parsing the ELF headers of the Ghost-C2 agent and manually mapping its `.text`, `.data`, and `.bss` segments directly into the target's memory space via `process_vm_writev`.
* [ ] **Execution Hijacking:** Modifying the target's Instruction Pointer (`RIP`) to execute the C2 agent flawlessly within a legitimate system process context.

**OpSec Advantage:** Zero disk footprint, complete bypass of `execve` based EDR telemetry, and no visible suspicious processes in the process tree.

NOTE ON "Phantom Loader": It's gonna take some time :D its not that easy to do it LOL but will do it.

[CANCELLED] Interactive TTY: Improving shell interaction to support full TTY features. >

🚫 Architectural Decision: Why No Interactive TTY?
The absence of an Interactive TTY (Pseudo-Terminal) in Ghost-C2 is not a limitation; it is a deliberate engineering and OPSEC decision to preserve the implant's absolute stealth. Implementing a full TTY would critically compromise the architecture for three main reasons:

Protocol Integrity (TCP-ification): ICMP is inherently a stateless, "fire-and-forget" protocol. A TTY requires a continuous, stateful, and strictly ordered data stream. Emulating TCP-like Sequence/ACK mechanisms over ICMP would bloat the pure Assembly footprint and destroy the lightweight nature of the tool.

OPSEC & "Ambient Noise" Destruction: An interactive shell generates traffic for every keystroke and screen update. This would create an "ICMP Storm," drastically raising the packet frequency and immediately triggering NIDS (e.g., Suricata) anomaly rules for abnormal ICMP volume. Ghost-C2 relies on blending into low-frequency diagnostic noise.

Behavioral Evasion (EDR): Allocating a PTY requires opening /dev/ptmx and executing specific ioctl syscalls. EDRs highly monitor these actions. Spawning an interactive shell without a legitimate parent daemon (like sshd) leaves massive behavioral artifacts in the kernel.

Conclusion: Ghost-C2 is designed as a hyper-stealth, stateless command execution and exfiltration implant—not a remote desktop administration tool. Adding a TTY trades absolute invisibility for convenience, which violates the core philosophy of this project.


## 🛡️ Technical Deep Dive: Evasion & Implementation (v3.0.0)
Ghost-C2 is designed to bypass modern Deep Packet Inspection (DPI) and Endpoint Detection and Response (EDR) systems by utilizing low-level x64 Assembly and advanced network protocol manipulation.

1. Protocol Mimicry & Padding Anatomy
Standard ICMP Echo Requests sent by the Linux iputils package have a predictable structure. Ghost-C2 mimics this signature to blend in with legitimate network diagnostic traffic.

Dynamic Timestamp: The first 8 bytes of the ICMP data segment are populated using the rdtsc (Read Time-Stamp Counter) instruction, mimicking the struct timeval used by real ping utilities.

Sequential Padding: From Offset 16 to 31, the implant injects a static 16-byte hex sequence (0x10 through 0x1F), which is the exact padding pattern expected by signature-based IDS/IPS filters.

The Stealth Gap: The actual encrypted C2 payload begins at Offset 32. By the time an automated scanner reaches this depth, it has likely already classified the packet as a "Standard Echo Request."

2. Fileless Execution via memfd_create
To minimize the forensic footprint, Ghost-C2 never touches the disk for command output storage.

Anonymous RAM Files: The agent utilizes sys_memfd_create (syscall 319) to create an anonymous file resident only in volatile memory (RAM).

I/O Redirection: Using sys_dup2 (syscall 33), the STDOUT and STDERR of the spawned /bin/sh process are redirected to this memory-backed file descriptor.

In-Memory Exfiltration: The agent reads the output back from RAM, obfuscates it using the _xor_cipher, and fragments it into ICMP Echo Replies for transmission back to the client.

3. Traffic Shaping & Jitter
Periodic "beaconing" is one of the easiest ways for SOC analysts to detect a C2 channel. Ghost-C2 disrupts this pattern:

Entropy Injection: By using rdtsc as a seed for the sys_nanosleep (syscall 35) duration, packet intervals become unpredictable.

Timing: Jitter intervals vary between 100ms and 300ms, simulating the natural latency and jitter of real-world network conditions.

4. Symmetric Rolling-Key Obfuscation
Both directions of communication are protected by a Symmetric Rolling XOR Cipher.

Intra-Packet Entropy: By using a shifting key (dl += 0x07) for every byte, it breaks static pattern matching and prevents simple XOR key discovery.

Signature Neutralization: Standard shell command signatures are obfuscated, ensuring the payload appears as high-entropy noise.

## 🚀 Getting Started

### 📋 Prerequisites

* **NASM** (Netwide Assembler)
* **LD** (GNU Linker)
* **Root Privileges** (Required to open RAW sockets)

### 🛡️Clean Masquerade
Tip: For a perfectly clean process tree without environment variable "bleeding", ensure the binary filename is at least 15 characters long (e.g., systemd-resolved-agent). This provides enough buffer on the stack to safely overwrite argv[0].
### 🎭 Dynamic Process Masquerading & Stealth
Ghost-C2 doesn't just run; it hides in plain sight. Using a combination of sys_prctl and argv[0] stack manipulation, the agent transforms itself into a legitimate system service.
Zero-Trace Memory Alignment:
The agent performs a deep memory sweep after the overwrite process. By manually null-terminating the argv[0] buffer and clearing the subsequent memory blocks, it ensures that no fragments of the original binary name or environment variables remain visible in process monitoring tools like ps, top, or htop.

💡 OPSEC Pro-Tip (Choosing the Right Mask): > 
To maximize evasion against behavioral heuristics, do not use random process names. Masquerade the agent as a native network daemon (e.g., systemd-networkd, NetworkManager, or dhclient). Since these legitimate services naturally interact with network interfaces and often utilize SOCK_RAW, your implant's network activity will blend into the system's baseline noise, drastically reducing the chance of triggering anomaly-based EDR alerts.

### 🛠️ Compilation & Usage

To assemble and link both the server and the client in one go:

```bash
# Assemble and Link the Agent
# Note: Using 'systemd-resolved' as the binary name for initial masquerading
nasm -f elf64 sniff.asm -o sniff.o && ld sniff.o -o systemd-resolved
```
```bash
nasm -f elf64 client.asm -o client.o && ld client.o -o client
```
## 💻 Usage
1- Deploy the Sniffer (Victim):
```bash
sudo ./systemd-resolved
```
2- Run the Controller (Attacker):
```bash
sudo ./client
```
3- Command Execution: Type your commands in the client terminal and watch the "ghost" reply from the victim.

### 🔍 Verification (The "Ghost" in the Machine)
Once running, the agent will vanish from standard process listings. Even if a system administrator looks for sniff, they will find nothing. Instead, they will see a legitimate-looking systemd-resolved process.
1. Check Process List:
```bash
$ ps aux | grep systemd-resolved
root        3887  0.0  0.0    192    16 ?        Ss   19:42   0:00 systemd-resolved
```
2. Deep Inspection (The Truth):
Only by inspecting the executable link in the /proc filesystem can the true identity be revealed:
```bash
$ sudo ls -l /proc/3887/exe
lrwxrwxrwx 1 root root 0 Mar 12 19:44 /proc/3887/exe -> /home/user/Downloads/ICMP-Ghost-A-Fileless-x64-Assembly-C2-Agent/systemd-resolved
```
## 📖 Deep Dive & Technical Analysis

For a detailed breakdown of the Assembly code, syscall mechanics, and the "Fileless" approach, check out the technical analysis on my blog:
## 👉 NetaCoding - https://netacoding.web.app/posts/icmp-ghost/
## 🤝 Connect with Me
GitHub: https://github.com/JM00NJ
Blog: https://netacoding.web.app/
## ⚠️ Legal Disclaimer
This project is created for educational purposes and security research only. Unauthorized access to computer systems is illegal. The author is not responsible for any misuse of this tool. Operating this tool on networks you do not own is strictly prohibited.

