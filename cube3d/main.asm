BITS 64
global _start

section .data
    AF_UNIX     equ 1
    SOCK_STREAM equ 1
    
    ; Syscalls
    SYS_READ    equ 0
    SYS_WRITE   equ 1
    SYS_MMAP    equ 9
    SYS_SOCKET  equ 41
    SYS_CONNECT equ 42
    SYS_RECVFROM equ 45
    SYS_EXIT    equ 60

    ; Codes Touches (A ajuster selon ton clavier si besoin)
    KEY_ESC     equ 9
    KEY_UP      equ 111
    KEY_DOWN    equ 116
    KEY_LEFT    equ 113
    KEY_RIGHT   equ 114

    ; Flags
    PROT_READ_WRITE equ 3
    MAP_PRIVATE_ANON equ 34
    MSG_DONTWAIT     equ 0x40

    sockaddr:
        dw AF_UNIX
        db "/tmp/.X11-unix/X0", 0
    sockaddr_len equ $ - sockaddr

    x11_auth_packet:
        db 0x6C, 0, 11, 0, 0, 0, 0, 0, 0, 0, 0, 0
    x11_auth_len equ $ - x11_auth_packet

    ; --- Variables ---
    server_response: times 32768 db 0
    window_id:      dd 0
    root_window_id: dd 0
    gc_id:          dd 0
    buffer_addr:    dq 0

    ; --- Paquets ---
    create_window_packet:
        db 1, 0, 10, 0
        dd 0, 0
        dw 0, 0, 800, 600, 0, 1
        dd 0
        dd 0x00000802
        dd 0x00FF0000
        dd 0x00008001
    create_window_len equ $ - create_window_packet

    map_window_packet:
        db 8, 0, 2, 0
        dd 0
    map_window_len equ $ - map_window_packet

    create_gc_packet:
        db 55, 0, 4, 0
        dd 0, 0, 0
    create_gc_len equ $ - create_gc_packet

    put_image_header:
        db 72, 2
        dw 0
        dd 0, 0
        dw 800, 10
        dw 0, 0
        db 0, 24, 0, 0
    put_image_header_len equ $ - put_image_header

    ; --- Variables du Jeu ---
    box_x:  dd 350
    box_y:  dd 250
    box_dx: dd 0        ; Vitesse X (0 au départ)
    box_dy: dd 0        ; Vitesse Y (0 au départ)
    box_w:  dd 50
    box_h:  dd 50

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

    ; 5. Parsing
    mov rbx, server_response
    cmp byte [rbx], 1
    jne error                   ; <--- Utilise le label error

    mov eax, [rbx + 12]
    inc eax
    mov [window_id], eax
    inc eax
    mov [gc_id], eax

    mov rdi, 40 
    movzx rcx, word [rbx + 24]
    add rdi, rcx
align_loop:
    test rdi, 3
    jz aligned
    inc rdi
    jmp align_loop
aligned:
    movzx rdx, byte [rbx + 29]
    shl rdx, 3
    add rdi, rdx
    
    mov eax, [rbx + rdi]
    mov [root_window_id], eax

    ; 6. Allocation Mémoire
    mov rax, SYS_MMAP
    mov rdi, 0
    mov rsi, 1920000
    mov rdx, PROT_READ_WRITE
    mov r10, MAP_PRIVATE_ANON
    mov r8, -1
    mov r9, 0
    syscall
    cmp rax, 0
    jl error                    ; <--- Utilise le label error
    mov [buffer_addr], rax

    ; 7. Setup X11
    mov eax, [window_id]
    mov [create_window_packet + 4], eax
    mov eax, [root_window_id]
    mov [create_window_packet + 8], eax
    
    mov rax, SYS_WRITE
    mov rdi, r12
    mov rsi, create_window_packet
    mov rdx, create_window_len
    syscall

    mov eax, [gc_id]
    mov [create_gc_packet + 4], eax
    mov eax, [window_id]
    mov [create_gc_packet + 8], eax

    mov rax, SYS_WRITE
    mov rdi, r12
    mov rsi, create_gc_packet
    mov rdx, create_gc_len
    syscall

    mov eax, [window_id]
    mov [map_window_packet + 4], eax

    mov rax, SYS_WRITE
    mov rdi, r12
    mov rsi, map_window_packet
    mov rdx, map_window_len
    syscall

    ; 8. Boucle de Jeu
game_loop:
    ; Clear Screen (Noir)
    mov rdi, [buffer_addr]
    mov rcx, 480000
    xor eax, eax
    rep stosd

    ; -----------------------------------------------
    ; PHYSIQUE : FROTTEMENT ET LIMITES
    ; -----------------------------------------------
    
    ; Appliquer la vitesse
    mov eax, [box_x]
    add eax, [box_dx]
    mov [box_x], eax
    
    mov eax, [box_y]
    add eax, [box_dy]
    mov [box_y], eax

    ; --- Limites X ---
    cmp dword [box_x], 0
    jge check_right
    mov dword [box_x], 0        ; Bloque à gauche
    jmp check_y_limit
check_right:
    cmp dword [box_x], 750
    jle check_y_limit
    mov dword [box_x], 750      ; Bloque à droite

check_y_limit:
    ; --- Limites Y ---
    cmp dword [box_y], 0
    jge check_bottom
    mov dword [box_y], 0        ; Bloque en haut
    jmp draw_box
check_bottom:
    cmp dword [box_y], 550
    jle draw_box
    mov dword [box_y], 550      ; Bloque en bas

    ; -----------------------------------------------
    ; DESSIN DU CARRE
    ; -----------------------------------------------
draw_box:
    xor r8, r8          ; r8 = compteur Y

loop_y:
    cmp r8d, [box_h]
    jge end_draw

    xor r9, r9          ; r9 = compteur X

loop_x:
    cmp r9d, [box_w]
    jge next_line

    ; Calcul adresse pixel
    mov eax, [box_y]
    add eax, r8d        ; Y actuel
    
    imul eax, 800       ; Y * Width
    
    mov ebx, [box_x]
    add ebx, r9d        ; + X actuel
    
    add eax, ebx        ; Index final
    shl eax, 2          ; * 4 octets
    
    mov rdi, [buffer_addr]
    add rdi, rax
    mov dword [rdi], 0x00FFFFFF ; Blanc

    inc r9
    jmp loop_x

next_line:
    inc r8
    jmp loop_y

end_draw:
    xor r15, r15

send_slices:
    cmp r15, 60
    jge events_check

    mov word [put_image_header + 2], 8006
    mov eax, [window_id]
    mov [put_image_header + 4], eax
    mov eax, [gc_id]
    mov [put_image_header + 8], eax
    
    mov eax, r15d
    imul eax, 10
    mov [put_image_header + 18], ax

    mov rax, SYS_WRITE
    mov rdi, r12
    mov rsi, put_image_header
    mov rdx, put_image_header_len
    syscall

    mov rax, 32000
    mul r15
    add rax, [buffer_addr]
    
    mov rsi, rax
    mov rax, SYS_WRITE
    mov rdi, r12
    mov rdx, 32000
    syscall

    inc r15
    jmp send_slices

    ; -----------------------------------------------
    ; LECTURE DES INPUTS (CLAVIER)
    ; -----------------------------------------------
events_check:
    mov rax, SYS_RECVFROM
    mov rdi, r12
    mov rsi, server_response
    mov rdx, 32768
    mov r10, MSG_DONTWAIT
    mov r8, 0
    mov r9, 0
    syscall

    cmp rax, 0
    jle game_loop           ; Rien reçu, on retourne dessiner

    ; --- Analyse du paquet ---
    cmp byte [server_response], 2   ; Est-ce un KeyPress ?
    jne game_loop                   ; Sinon, on ignore

    ; --- Lecture du Keycode (Octet 1) ---
    movzx rbx, byte [server_response + 1] ; rbx contient le code de la touche

    ; --- Comparaison des touches ---
    cmp rbx, KEY_ESC
    je close_app
    cmp rbx, KEY_LEFT
    je go_left
    cmp rbx, KEY_RIGHT
    je go_right
    cmp rbx, KEY_UP
    je go_up
    cmp rbx, KEY_DOWN
    je go_down

    jmp game_loop

; --- Actions ---
go_left:
    mov dword [box_dx], -2
    mov dword [box_dy], 0
    jmp game_loop

go_right:
    mov dword [box_dx], 2
    mov dword [box_dy], 0
    jmp game_loop

go_up:
    mov dword [box_dx], 0
    mov dword [box_dy], -2
    jmp game_loop

go_down:
    mov dword [box_dx], 0
    mov dword [box_dy], 2
    jmp game_loop

close_app:
    mov rax, SYS_EXIT
    mov rdi, 0
    syscall

; --- C'EST ICI QUE TU AVAIS OUBLIÉ LE LABEL ERROR ---
error:
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall