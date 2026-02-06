BITS 64
global _start

section .data
    AF_UNIX     equ 1
    SOCK_STREAM equ 1
    
    SYS_READ    equ 0
    SYS_WRITE   equ 1
    SYS_SOCKET  equ 41
    SYS_CONNECT equ 42
    SYS_EXIT    equ 60

    sockaddr:
        dw AF_UNIX
        db "/tmp/.X11-unix/X0", 0
    sockaddr_len equ $ - sockaddr

    x11_auth_packet:
        db 0x6C, 0, 11, 0, 0, 0, 0, 0, 0, 0, 0, 0
    x11_auth_len equ $ - x11_auth_packet

    ; --- Buffers de réponse et variables ---
    server_response: times 32768 db 0
    window_id:      dd 0
    root_window_id: dd 0
    root_visual_id: dd 0

    ; --- Paquets à envoyer ---
    create_window_packet:
        db 1, 0         ; Opcode(1), Depth(0)
        dw 10           ; <--- CORRECTION ICI ! (Avant c'était 9)
                        ; 10 blocs de 4 octets = 40 octets total
        
        dd 0, 0         ; WID, Parent
        dw 0, 0, 800, 600, 0, 1 ; x, y, w, h, border, class
        dd 0            ; Visual
        dd 0x00000802   ; Mask
        dd 0x00FF0000   ; Value 1: Rouge
        dd 0x00008001   ; Value 2: Events
    create_window_len equ $ - create_window_packet

    map_window_packet:
        db 8, 0, 2, 0   ; Opcode(8), Unused, Len(2)
        dd 0            ; WID (A REMPLIR)
    map_window_len equ $ - map_window_packet

section .text
_start:
    ; 1. Socket
    mov rax, SYS_SOCKET
    mov rdi, AF_UNIX
    mov rsi, SOCK_STREAM
    mov rdx, 0
    syscall
    mov r12, rax

    ; 2. Connect
    mov rax, SYS_CONNECT
    mov rdi, r12
    mov rsi, sockaddr
    mov rdx, sockaddr_len
    syscall

    ; 3. Handshake
    mov rax, SYS_WRITE
    mov rdi, r12
    mov rsi, x11_auth_packet
    mov rdx, x11_auth_len
    syscall

    ; 4. Read Response
    mov rax, SYS_READ
    mov rdi, r12
    mov rsi, server_response
    mov rdx, 32768
    syscall

    ; ---------------------------------------------------------
    ; 5. PARSING (NETTOYÉ ET CORRIGÉ)
    ; ---------------------------------------------------------
    mov rbx, server_response
    
    cmp byte [rbx], 1
    jne error

    ; --- Récupérer ID Base ---
    mov eax, [rbx + 12]
    inc eax
    mov [window_id], eax

    ; --- Calculer l'adresse de SCREEN ---
    ; Header fixe = 40 octets (8 prefix + 32 setup)
    mov rdi, 40 
    
    ; Ajouter longueur Vendor (Offset 24)
    movzx rcx, word [rbx + 24]
    add rdi, rcx
    
    ; Alignement sur 4 octets (Padding manuel)
align_loop:
    test rdi, 3
    jz aligned
    inc rdi
    jmp align_loop
aligned:
    
    ; Ajouter la taille des formats (Offset 29)
    movzx rdx, byte [rbx + 29]
    shl rdx, 3   ; rdx * 8
    add rdi, rdx ; On saute les formats
    
    ; --- Lecture finale des infos ---
    ; ICI rdi pointe sur le début de SCREEN.
    
    mov eax, [rbx + rdi]
    mov [root_window_id], eax
    
    ; On lit le Visual ID juste pour info, mais on ne l'utilisera pas
    mov eax, [rbx + rdi + 32]
    mov [root_visual_id], eax

    ; ---------------------------------------------------------
    ; 6. CREATION FENETRE
    ; ---------------------------------------------------------
    mov eax, [window_id]
    mov [create_window_packet + 4], eax
    
    mov eax, [root_window_id]
    mov [create_window_packet + 8], eax
    
    ; --- FIX CRITIQUE : NE PAS TOUCHER AU VISUAL ID ---
    ; On laisse la valeur 0 dans le paquet (CopyFromParent).
    ; Cela évite l'erreur "BadMatch" car on hérite du parent.
    ; mov eax, [root_visual_id]       <-- SUPPRIMÉ
    ; mov [create_window_packet + 24], eax <-- SUPPRIMÉ

    mov rax, SYS_WRITE
    mov rdi, r12
    mov rsi, create_window_packet
    mov rdx, create_window_len
    syscall

    ; ---------------------------------------------------------
    ; 7. AFFICHAGE (MAP)
    ; ---------------------------------------------------------
    mov eax, [window_id]
    mov [map_window_packet + 4], eax

    mov rax, SYS_WRITE
    mov rdi, r12
    mov rsi, map_window_packet
    mov rdx, map_window_len
    syscall

    ; ---------------------------------------------------------
    ; 8. BOUCLE
    ; ---------------------------------------------------------
loop_start:
    mov rax, SYS_READ
    mov rdi, r12
    mov rsi, server_response
    mov rdx, 32768
    syscall
    
    cmp rax, 0
    jle error

    ; Si code 2 (KeyPress), on sort
    cmp byte [server_response], 2
    je exit_ok

    jmp loop_start

exit_ok:
    mov rax, SYS_EXIT
    mov rdi, 0
    syscall

error:
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall