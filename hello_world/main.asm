; code minimal pour linux
; syscalls
BITS 64
global _start

section .data
    message db "hello world", 10 ; message à afficher suivi d'un saut de ligne
    message_len equ $ - message ; longueur du message
    SYS_WRITE equ 1 ; syscall: write
    STD_OUTPUT equ 1 ; file descriptor: stdout
    SYS_EXIT equ 60 ; syscall: exit
    

section .text
_start:    ; afficher un message
    mov r15, 5 ; Compteur de boucle à 5

.boucle_affichage:      ; Ceci est notre point de repère pour le saut
    mov rax, SYS_WRITE ; syscall: write
    mov rdi, STD_OUTPUT
    mov rsi, message
    mov rdx, message_len
    syscall 
    dec r15         ; On enlève 1 au compteur
    jnz .boucle_affichage ; Si r15 n'est pas 0, on retourne à l'étiquette

    ; quitter le programme
    mov rax, SYS_EXIT ; syscall: exit
    xor rdi, rdi ; status: 0
    syscall
