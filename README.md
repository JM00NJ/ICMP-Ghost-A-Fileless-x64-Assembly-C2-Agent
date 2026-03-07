# 🚀 ICMP-Ghost: A Fileless x64 Assembly C2 Agent

![Architecture](https://img.shields.io/badge/Architecture-x86__64-red.svg)
![Language](https://img.shields.io/badge/Language-Pure%20Assembly-green.svg)
![Protocol](https://img.shields.io/badge/Protocol-ICMP-blue.svg)
![OS](https://img.shields.io/badge/OS-Linux-orange.svg)

**ICMP-Ghost** is a minimalist, stealthy Command & Control (C2) agent written entirely in **x64 Assembly** for Linux. It utilizes the ICMP protocol (Ping) for communication, bypassing traditional TCP/UDP-based detection by operating at the raw socket level.

## Star vs. Clone
I see you're interested in the code! If you're one of the many people cloning this repo, consider dropping a Star as well. It helps the project stay visible and reach more low-level enthusiasts

---

⚠️ Known Issues & Current Limitations
Asymmetric Encryption Disparity: In the current version (v2.1.0), only the ICMP Echo Reply (Agent-to-Client response) is fully XOR-obfuscated. The ICMP Echo Request (Client-to-Agent command) currently transmits in plain-text.

Impact: Advanced Deep Packet Inspection (DPI) or IDS systems may flag common shell command strings (e.g., whoami, ls) within the initial trigger packet.

Mitigation: This is a known technical debt and is scheduled to be resolved in the upcoming v2.2.0 patch by implementing request-side XOR encryption and agent-side decryption.

## 🏗️ Architecture Overview: Passive Trigger-Based Implant (v2.1.0)
Ghost-C2 is a fileless, x64 assembly-based server-side implant that leverages raw ICMP sockets for stealthy command and control. Unlike traditional reverse-beacons, Ghost-C2 remains entirely passive, acting as a stateless listener that only responds to a specific Magic Sequence.

🛡️ Current Stealth Capabilities (v2.1.0)
Stateless Evasion: Operating purely on raw ICMP sockets bypasses stateful firewall tracking common in TCP/UDP connections.

MTU-Aware Payload Chunking: Data is automatically fragmented into 1024-byte chunks, preventing protocol anomalies and ensuring reliability across diverse network MTUs.

Stream Obfuscation: All exfiltrated data is obfuscated using an in-place XOR cipher, breaking static string-based signatures.

Full I/O Redirection: Captures both STDOUT and STDERR, ensuring visibility even during command failures.

EOS (End-of-Stream) Signaling: Prevents protocol hangs by dispatching specialized termination packets for boundary-aligned data streams.

## 🗺️ Future Roadmap: The "Stealth" Update (v3.0+)
The upcoming major release (v3.0) is focused on defeating Deep Packet Inspection (DPI) and advanced SOC/IDS behavioral heuristics through sophisticated evasion techniques:

Protocol Mimicry (Padding): Encapsulating encrypted payloads within standard Linux ping data patterns (timestamp + sequence padding) to mimic legitimate diagnostic traffic.

Polymorphic Obfuscation: Transitioning from static XOR keys to dynamic, per-packet rolling keys derived from the ICMP Sequence Number, effectively breaking static entropy-based signatures.

Traffic Shaping (Jitter): Implementing randomized transmission intervals (100-300ms jitter) to disrupt periodic beaconing detection and simulate human-like network activity.

IP-Layer Fragmentation: Shifting from application-layer chunking to native IP-level fragmentation to blind legacy IDS/IPS systems and evade payload-length heuristics.

## 🎯 Target Environments & Operational Viability

This C2 framework is highly effective against standard Linux web servers, standalone cloud VMs, and SMB infrastructure where deep packet inspection (DPI) or enterprise-grade IDS/IPS is not actively deployed. 

**Ideal Deployment Scenarios:**
* Web servers running e-commerce platforms or CMS (WordPress, Magento, etc.) with standard `iptables`/`ufw` configurations.
* Cloud droplets where ICMP Echo is permitted for monitoring purposes.
* Environments lacking kernel-level behavioral monitoring (EDR).

*Note: In heavily monitored enterprise environments (e.g., Zero Trust architectures with strict ICMP payload inspections or active SOC monitoring), the static nature of the initial magic sequence may be flagged as a protocol anomaly.*


## 📺 Demo
Here is the agent in action, showcasing its stealthy daemonization and remote command execution:

<p align="center">
  <img src="ghost_demo.gif" alt="ICMP Ghost Demo" width="800">
  <br><br>
  <img src="ghost_demo1.gif" alt="ICMP Ghost Demo Alternate" width="800">
</p>

---

## 🛠 Features

* **100% Pure Assembly:** No Libc, no external dependencies. Direct Linux Kernel interaction via raw **Syscalls**.
* **Fileless Execution:** Leveraging `memfd_create` to execute commands and store outputs entirely in RAM. No trace left on the physical disk.
* **Stealth Communication:** Uses ICMP Type 8 (Request) and Type 0 (Reply) to blend into legitimate network traffic.
* **Daemonization:** Automatically detaches from the terminal and transitions into a background process using `setsid`.
* **I/O Redirection:** Hijacks `stdout` using `dup2` to capture shell output silently and transport it via ICMP.

---

## 🏗 How It Works (The "Ghost" Logic)

The agent follows a sophisticated execution flow to remain undetected by basic monitoring tools:

1.  **Daemonize:** On startup, it forks itself and calls `setsid` to become a background daemon, losing its controlling terminal.
2.  **Raw Socket Sniffing:** Opens a **RAW socket** to sniff incoming ICMP packets, filtering for a specific `Magic Sequence`.
3.  **Memory Execution:** When a command is received, it creates an anonymous file in RAM using `memfd_create`.
4.  **Process Redirection:** Forks a child process, redirects `stdout` to the memory file descriptor, and executes the command via `execve`.
5.  **Exfiltration:** The parent reads the output from RAM, packages it into an ICMP Echo Reply, and fires it back to the attacker dynamically.



---

## 🚀 Getting Started

### 📋 Prerequisites

* **NASM** (Netwide Assembler)
* **LD** (GNU Linker)
* **Root Privileges** (Required to open RAW sockets)

### 🛠 Compilation

To assemble and link both the server and the client in one go:

```bash
nasm -f elf64 sniff.asm -o sniff.o && ld sniff.o -o sniff && nasm -f elf64 client.asm -o client.o && ld client.o -o client
```
## 💻 Usage
1- Deploy the Sniffer (Victim):
```bash
sudo ./sniff
```
2- Run the Controller (Attacker):
```bash
sudo ./client
```
3- Command Execution: Type your commands in the client terminal and watch the "ghost" reply from the victim.

## 🗺️ Roadmap & Future Enhancements
This project is under active development. Future releases will focus on advanced evasion techniques:

[ ] Dynamic Process Masquerading: Renaming the process at runtime (e.g., to [kworker] or systemd) to blend in.

[DONE] Payload Encryption: Implementing XOR or AES encryption for ICMP data to bypass Deep Packet Inspection (DPI).

[ ] Anti-Debugging & Anti-VM: Adding ptrace checks and environmental artifact detection.

[ ] Interactive TTY: Improving shell interaction to support full TTY features and stderr redirection.

[ ] Persistence Mechanisms: Adding pure assembly-based persistence methods for various Linux distros.

[ ] Stealth Triggering (Port Knocking): Implementing a sequential packet size/count handshake to wake the agent from deep sleep. This ensures the agent remains completely silent until the "master" knocks.

[DONE] Data Fragmentation (Chunking): Splitting large command outputs into multiple 1024-byte ICMP packets to bypass MTU (1500) limits and ensure reliable data exfiltration across real-world networks.

[ ] Multi-Target Management: Enhancing the client to track and manage multiple infected hosts simultaneously using their source IP as a unique identifier.

## 📖 Deep Dive & Technical Analysis

For a detailed breakdown of the Assembly code, syscall mechanics, and the "Fileless" approach, check out the technical analysis on my blog:
## 👉 NetaCoding - https://netacoding.blogspot.com/2026/03/icmp-ghostc2-fileless.html
## 🤝 Connect with Me
GitHub: https://github.com/JM00NJ
Blog: https://netacoding.blogspot.com/
## ⚠️ Legal Disclaimer
This project is created for educational purposes and security research only. Unauthorized access to computer systems is illegal. The author is not responsible for any misuse of this tool. Operating this tool on networks you do not own is strictly prohibited.

