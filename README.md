# 👻 Ghost-C2: Fileless x64 Assembly ICMP C2 (v3.0.0)

![Architecture](https://img.shields.io/badge/Architecture-x86__64-red.svg)
![Language](https://img.shields.io/badge/Language-Pure%20Assembly-green.svg)
![Protocol](https://img.shields.io/badge/Protocol-ICMP-blue.svg)
![OS](https://img.shields.io/badge/OS-Linux-orange.svg)

**Ghost-C2 is a fileless, server-side implant written in pure x64 Assembly. It leverages raw ICMP sockets for stealthy command and control, acting as a passive, stateless listener that only responds to a specific Magic Sequence.

## Star vs. Clone
I see you're interested in the code! If you're one of the many people cloning this repo, consider dropping a Star as well. It helps the project stay visible and reach more low-level enthusiasts

---


## 🏗️ Architecture Overview: Passive Trigger-Based Implant (v2.1.0)
Ghost-C2 is a fileless, x64 assembly-based server-side implant that leverages raw ICMP sockets for stealthy command and control. Unlike traditional reverse-beacons, Ghost-C2 remains entirely passive, acting as a stateless listener that only responds to a specific Magic Sequence.

🚀 The "Stealth" Update (v3.0.0) - What's New?
With the latest release, Ghost-C2 has reached a new level of operational security, effectively defeating Deep Packet Inspection (DPI) and behavioral heuristics:

[DONE] Protocol Mimicry (Padding): Encapsulates encrypted payloads within standard Linux ping data patterns. It mimics legitimate diagnostic traffic by including a dynamic timestamp (RDTSC) and a 24-byte sequence padding (0x10-0x1F).

[DONE] Traffic Shaping (Jitter): Implements randomized transmission intervals (100-300ms jitter) using rdtsc to disrupt periodic beaconing detection and simulate human-like network activity.

[DONE] Bi-directional Stream Obfuscation: The "Asymmetric Encryption Disparity" has been resolved. Both ICMP Echo Request (Client-to-Agent) and Echo Reply (Agent-to-Client) are now fully XOR-obfuscated.

[DONE] Data Fragmentation (Chunking): Automatically splits large command outputs into 1000-byte ICMP packets to bypass MTU limits and ensure reliable exfiltration.

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

🛠 Architecture Overview
Stateless Evasion: Operates purely on raw ICMP sockets, bypassing stateful firewall tracking common in TCP/UDP connections.

Fileless Execution: Uses sys_memfd_create to capture command output in RAM, ensuring no disk artifacts are left behind.

Full I/O Redirection: Captures both STDOUT and STDERR, ensuring full visibility even during command failures.

Magic Trigger: The agent remains completely silent until it receives an ICMP packet with the correct Magic Sequence (0xDEAD).

---

🗺 Roadmap & Future Enhancements
[ ] Dynamic Process Masquerading: Renaming the process at runtime (e.g., to [kworker] or systemd).

[ ] Anti-Debugging & Anti-VM: Adding ptrace checks and environmental artifact detection.

[ ] Interactive TTY: Improving shell interaction to support full TTY features.

[ ] Polymorphic Obfuscation: Transitioning from static XOR keys to dynamic, per-packet rolling keys.

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

## 📖 Deep Dive & Technical Analysis

For a detailed breakdown of the Assembly code, syscall mechanics, and the "Fileless" approach, check out the technical analysis on my blog:
## 👉 NetaCoding - https://netacoding.blogspot.com/2026/03/icmp-ghostc2-fileless.html
## 🤝 Connect with Me
GitHub: https://github.com/JM00NJ
Blog: https://netacoding.blogspot.com/
## ⚠️ Legal Disclaimer
This project is created for educational purposes and security research only. Unauthorized access to computer systems is illegal. The author is not responsible for any misuse of this tool. Operating this tool on networks you do not own is strictly prohibited.

