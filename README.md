# 🚀 ICMP-Ghost: A Fileless x64 Assembly C2 Agent

![Architecture](https://img.shields.io/badge/Architecture-x86__64-red.svg)
![Language](https://img.shields.io/badge/Language-Pure%20Assembly-green.svg)
![Protocol](https://img.shields.io/badge/Protocol-ICMP-blue.svg)
![OS](https://img.shields.io/badge/OS-Linux-orange.svg)

**ICMP-Ghost** is a minimalist, stealthy Command & Control (C2) agent written entirely in **x64 Assembly** for Linux. It utilizes the ICMP protocol (Ping) for communication, bypassing traditional TCP/UDP-based detection by operating at the raw socket level.

---

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

[ ] Payload Encryption: Implementing XOR or AES encryption for ICMP data to bypass Deep Packet Inspection (DPI).

[ ] Anti-Debugging & Anti-VM: Adding ptrace checks and environmental artifact detection.

[ ] Interactive TTY: Improving shell interaction to support full TTY features and stderr redirection.

[ ] Persistence Mechanisms: Adding pure assembly-based persistence methods for various Linux distros.

## 📖 Deep Dive & Technical Analysis

For a detailed breakdown of the Assembly code, syscall mechanics, and the "Fileless" approach, check out the technical analysis on my blog:
## 👉 NetaCoding - https://netacoding.blogspot.com/
## 🤝 Connect with Me
GitHub: https://github.com/JM00NJ
Blog: https://netacoding.blogspot.com/
## ⚠️ Legal Disclaimer
This project is created for educational purposes and security research only. Unauthorized access to computer systems is illegal. The author is not responsible for any misuse of this tool. Operating this tool on networks you do not own is strictly prohibited.

