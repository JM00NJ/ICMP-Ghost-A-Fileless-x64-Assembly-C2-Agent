# 🚀 ICMP-Ghost: A Fileless x64 Assembly C2 Agent

![Architecture](https://img.shields.io/badge/Architecture-x86__64-red.svg)
![Language](https://img.shields.io/badge/Language-Pure%20Assembly-green.svg)
![Protocol](https://img.shields.io/badge/Protocol-ICMP-blue.svg)
![OS](https://img.shields.io/badge/OS-Linux-orange.svg)

**ICMP-Ghost** is a minimalist, stealthy Command & Control (C2) agent written entirely in **x64 Assembly** for Linux. It utilizes the ICMP protocol (Ping) for communication, bypassing traditional TCP/UDP-based detection by operating at the raw socket level.

## Star vs. Clone
I see you're interested in the code! If you're one of the many people cloning this repo, consider dropping a Star as well. It helps the project stay visible and reach more low-level enthusiasts

---

## 🏗️ Architecture Overview: Trigger-Based Server Implant

ICMP-Ghost is explicitly designed as a **Server-Side Triggered Implant**, moving away from traditional reverse-beaconing methodologies that target NAT-restricted end-user devices. 

In real-world Red Team operations involving Linux infrastructure, the targets are typically cloud instances (AWS, DigitalOcean, Linode) or DMZ servers with public IPs. ICMP-Ghost leverages this topology by acting as a passive, bind-like listener on the compromised server. 

* **No Active Beaconing:** The agent never initiates outbound traffic, keeping it invisible to outbound firewall rules.
* **Public IP to Public IP:** Designed for Server-to-Server communication. The attacker utilizes a remote redirector (VPS) to send the "Magic Sequence" (Trigger) directly to the infected server's public IP.
* **Stateless Evasion:** Bypasses stateful firewall tracking issues common in traditional reverse shells by operating purely on raw, stateless ICMP sockets.
*For now Note: In heavily monitored enterprise environments (e.g., Zero Trust architectures with strict ICMP payload inspections or active SOC monitoring), the static nature of the initial magic sequence may be flagged as a protocol anomaly. **However, upcoming major releases (v3.0+) are actively addressing this by introducing polymorphic signaling, stealth port-knocking rituals, and payload chunking to defeat DPI and behavioral heuristics.***

## 🎯 Target Environments & Operational Viability

This C2 framework is highly effective against standard Linux web servers, standalone cloud VMs, and SMB infrastructure where deep packet inspection (DPI) or enterprise-grade IDS/IPS is not actively deployed. 

**Ideal Deployment Scenarios:**
* Web servers running e-commerce platforms or CMS (WordPress, Magento, etc.) with standard `iptables`/`ufw` configurations.
* Cloud droplets where ICMP Echo is permitted for monitoring purposes.
* Environments lacking kernel-level behavioral monitoring (EDR).

*Note: In heavily monitored enterprise environments (e.g., Zero Trust architectures with strict ICMP payload inspections or active SOC monitoring), the static nature of the initial magic sequence may be flagged as a protocol anomaly.*

### 🔍 IP Configuration (Little-Endian Conversion)

Since x86-64 architecture uses **Little-endian** byte ordering, you must provide the Target IP address in **reversed hex order** in `client.asm`.

```nasm
target_addr:
    dw 2              ; AF_INET
    dw 0              ; Port
    dd 0x1901A8C0     ; <--- CHANGE THIS HEX (e.g., 192.168.1.25)
```

| Target IP | Octets in Hex | Normal Hex (Big-Endian) | **Reversed Hex (Little-Endian)** |
| :--- | :--- | :--- | :--- |
| **192.168.1.25** | `C0` `A8` `01` `19` | `0xC0A80119` | **`0x1901A8C0`** |
| **10.0.0.5** | `0A` `00` `00` `05` | `0x0A000005` | **`0x0500000A`** |
| **172.16.0.100** | `AC` `10` `00` `64` | `0xAC100064` | **`0x640010AC`** |

#### 🚀 Quick Conversion via Python
You can use this one-liner to get the correct hex value for any IP immediately:
```bash
python3 -c "import socket, struct; print(hex(struct.unpack('<I', socket.inet_aton('YOUR_IP_HERE'))[0]))"
```



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

[ ] Data Fragmentation (Chunking): Splitting large command outputs into multiple 1024-byte ICMP packets to bypass MTU (1500) limits and ensure reliable data exfiltration across real-world networks.

[ ] Multi-Target Management: Enhancing the client to track and manage multiple infected hosts simultaneously using their source IP as a unique identifier.

## 📖 Deep Dive & Technical Analysis

For a detailed breakdown of the Assembly code, syscall mechanics, and the "Fileless" approach, check out the technical analysis on my blog:
## 👉 NetaCoding - https://netacoding.blogspot.com/2026/03/icmp-ghostc2-fileless.html
## 🤝 Connect with Me
GitHub: https://github.com/JM00NJ
Blog: https://netacoding.blogspot.com/
## ⚠️ Legal Disclaimer
This project is created for educational purposes and security research only. Unauthorized access to computer systems is illegal. The author is not responsible for any misuse of this tool. Operating this tool on networks you do not own is strictly prohibited.

