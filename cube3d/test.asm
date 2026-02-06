BITS 64
global _start

section .data
    ; Constantes
    AF_UNIX     equ 1
    SOCK_STREAM equ 1
    
    ; Syscalls
    SYS_READ    equ 0
    SYS_WRITE   equ 1
    SYS_SOCKET  equ 41
    SYS_CONNECT equ 42
    SYS_EXIT    equ 60

    ; Structure d'adresse pour se connecter (sockaddr_un)
    sockaddr:
        dw AF_UNIX                  ; Famille (2 octets)
        db "/tmp/.X11-unix/X0", 0   ; Chemin du socket
    sockaddr_len equ $ - sockaddr

    ; Structure du Handshake (Client Hello)
    x11_auth_packet:
        db 0x6C      ; 'l' = Little Endian
        db 0         ; Unused
        dw 11        ; Version 11
        dw 0         ; Subversion 0
        dw 0         ; Auth name len
        dw 0         ; Auth data len
        dw 0         ; Unused
    x11_auth_len equ $ - x11_auth_packet

section .bss
    ; Buffer pour recevoir la réponse du serveur (32 Ko)
    server_response resb 32768

section .text
_start:
    ; 1. Créer le socket
    mov rax, SYS_SOCKET
    mov rdi, AF_UNIX
    mov rsi, SOCK_STREAM
    mov rdx, 0
    syscall
    
    mov r12, rax           ; Sauvegarder le FD dans r12

    ; 2. Se connecter
    mov rax, SYS_CONNECT
    mov rdi, r12
    mov rsi, sockaddr
    mov rdx, sockaddr_len
    syscall

    ; 3. Envoyer le Handshake
    mov rax, SYS_WRITE
    mov rdi, r12
    mov rsi, x11_auth_packet
    mov rdx, x11_auth_len
    syscall

    ; 4. Lire la réponse
    mov rax, SYS_READ
    mov rdi, r12
    mov rsi, server_response
    mov rdx, 32768
    syscall

    ; 5. Vérifier le succès
    ; Le premier octet de la réponse DOIT être 1
    mov al, [server_response]
    cmp al, 1
    je success

error:
    ; Quitter avec code 1 (Erreur)
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

success:
    ; Quitter avec code 0 (Succès)
    mov rax, SYS_EXIT
    mov rdi, 0
    syscall