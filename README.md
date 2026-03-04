# 🚀 ICMP-Ghost: A Fileless x64 Assembly C2 Agent
ICMP-Ghost is a minimalist, stealthy Command & Control (C2) agent written entirely in x64 Assembly for Linux. It utilizes the ICMP protocol (Ping) for communication, bypassing traditional TCP/UDP-based detection.

![ICMP Ghost Demo](ghost_demo.gif)
![ICMP Ghost Demo](ghost_demo1.gif)

# 🛠 Features
100% Pure Assembly: No Libc, no external dependencies. Direct Linux Kernel interaction via Syscalls.

Fileless Execution: Leveraging memfd_create to execute commands and store outputs entirely in RAM. No trace on the disk.

Stealth Communication: Uses ICMP Type 8 (Request) and Type 0 (Reply) for data exfiltration and C&C.

Daemonization: Automatically detaches from the terminal and runs as a background process using setsid.

I/O Redirection: Hijacks stdout using dup2 to capture shell output silently.

# 🏗 How It Works (The "Ghost" Logic)
The agent follows a sophisticated execution flow to remain undetected by basic monitoring tools:

Daemonize: On startup, it forks itself and calls setsid to become a background daemon.

Raw Socket Sniffing: Opens a RAW socket to sniff incoming ICMP packets, filtering for a specific Magic Sequence.

Memory Execution: When a command is received, it creates an anonymous file in RAM using memfd_create.

Process Redirection: Forks a child process, redirects stdout to the memfd file descriptor, and executes the command via execve.

Exfiltration: The parent reads the output from RAM, packages it into an ICMP Echo Reply, and fires it back to the attacker dynamically.

# 🚀 Getting Started
# Prerequisites

  NASM (Netwide Assembler)

  LD (GNU Linker)

  Root privileges (Required for RAW Sockets)

# Compilation
```bash
nasm -f elf64 sniff.asm -o sniff.o && ld sniff.o -o sniff && nasm -f elf64 client.asm -o client.o && ld client.o -o client
```
# Usage
1- Run the sniff on the victim machine: sudo ./sniff

2-Run the client on your machine: sudo ./client

3-Type your commands and watch the "ghost" reply.

# ⚠️ Legal Disclaimer
# This project is created for educational purposes and security research only. Unauthorized access to computer systems is illegal. The author is not responsible for any misuse of this tool.

# 📖 Deep Dive & Technical Analysis
For a detailed breakdown of the Assembly code, syscall mechanics, and the "Fileless" approach, check out my technical blog post:
# 👉 https://netacoding.blogspot.com/

# 🤝 Connect with Me
GitHub: https://github.com/JM00NJ
Blog: https://netacoding.blogspot.com/
