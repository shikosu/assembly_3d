BITS 64
global _start

; --- DÉFINITION DE LA STRUCTURE ---
struc Sphere
    .cx:    resd 1      ; Centre X
    .cy:    resd 1      ; Centre Y
    .cz:    resd 1      ; Centre Z (futur)
    .r2:    resd 1      ; Rayon au carré
    .id:    resd 1      ; ID/Couleur
endstruc

section .data
    SYS_OPEN equ 2
    SYS_WRITE equ 1
    SYS_CLOSE equ 3
    SYS_EXIT equ 60
    O_CREAT_WRONLY equ 65
    PERMS equ 420
    WIDTH equ 256
    HEIGHT equ 256
    PIXEL_COUNT equ WIDTH * HEIGHT
    BUFFER_SIZE equ PIXEL_COUNT * 3
    
    filename db "render.ppm", 0
    header db "P6 256 256 255", 10
    header_len equ $ - header

    ; Vecteurs Lumière
    LIGHT_X dd -0.577
    LIGHT_Y dd -0.577
    LIGHT_Z dd -0.577
    
    ; Note: INV_RADIUS est approximatif ici (calibré pour rayon 50)
    INV_RADIUS dd 0.02
    COLOR_SCALE dd 255.0

    ; --- NOS DEUX SPHÈRES ---
    sphere1:
        istruc Sphere
            at Sphere.cx, dd 100.0   ; Gauche
            at Sphere.cy, dd 128.0   ; Centre Y
            at Sphere.cz, dd 0.0
            at Sphere.r2, dd 1600.0  ; Rayon 40
            at Sphere.id, dd 1
        iend

    sphere2:
        istruc Sphere
            at Sphere.cx, dd 180.0   ; Droite
            at Sphere.cy, dd 160.0   ; Bas
            at Sphere.cz, dd 0.0
            at Sphere.r2, dd 900.0   ; Rayon 30
            at Sphere.id, dd 2
        iend

section .bss
    pixel_buffer resb BUFFER_SIZE

section .text
_start:
    ; --- 1. SETUP CLASSIQUE ---
    mov rax, SYS_OPEN
    mov rdi, filename
    mov rsi, O_CREAT_WRONLY
    mov rdx, PERMS
    syscall
    mov r12, rax         ; Sauvegarde FD

    mov rax, SYS_WRITE
    mov rdi, r12
    mov rsi, header
    mov rdx, header_len
    syscall

    lea r15, [rel pixel_buffer]

    ; --- 2. DOUBLE BOUCLE (MAIN LOOP) ---
    xor r13, r13        ; Y = 0

loop_y:
    cmp r13, HEIGHT
    jge end_y
    xor r14, r14        ; X = 0

loop_x:
    cmp r14, WIDTH
    jge end_x

    ; ========================================================
    ; GESTIONNAIRE DE SCÈNE
    ; ========================================================
    
    ; --- TEST SPHÈRE 1 ---
    lea rdi, [rel sphere1]      ; On charge l'adresse de Sphere 1
    call trace_ray              ; On appelle la fonction
    test al, al                 ; Résultat > 0 ?
    jnz .draw_pixel             ; Si oui, on dessine et on passe au suivant

    ; --- TEST SPHÈRE 2 (Seulement si Sphère 1 ratée) ---
    lea rdi, [rel sphere2]      ; On charge l'adresse de Sphere 2
    call trace_ray
    test al, al                 ; Résultat > 0 ?
    jnz .draw_pixel             ; Si oui, on dessine

    ; --- SINON: FOND NOIR ---
    mov byte [r15], 0
    mov byte [r15+1], 0
    mov byte [r15+2], 0
    jmp .next_pixel

.draw_pixel:
    ; Ici AL contient l'intensité retournée par trace_ray
    mov [r15], al        ; Rouge
    mov byte [r15+1], 0  ; Vert (Noir pour l'instant)
    mov byte [r15+2], 0  ; Bleu (Noir pour l'instant)

.next_pixel:
    add r15, 3
    inc r14
    jmp loop_x

end_x:
    inc r13
    jmp loop_y

end_y:
    ; --- FIN ET SORTIE ---
    mov rax, SYS_WRITE
    mov rdi, r12
    lea rsi, [rel pixel_buffer]
    mov rdx, BUFFER_SIZE
    syscall

    mov rax, SYS_CLOSE
    mov rdi, r12
    syscall

    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall

; ====================================================================
; FONCTION TRACE_RAY (Optimisée Struct)
; ====================================================================
; Entrées:
;   R14 = X, R13 = Y
;   RDI = Adresse de la structure Sphere à tester !
; Sortie: AL = Intensité (0-255)
; ====================================================================
trace_ray:
    ; --- CALCUL X ---
    cvtsi2ss xmm0, r14
    subss xmm0, [rdi + Sphere.cx]       ; Utilise le CX de la sphère pointée !
    movss xmm3, xmm0                    ; Nx
    mulss xmm0, xmm0
    
    ; --- CALCUL Y ---
    cvtsi2ss xmm1, r13
    subss xmm1, [rdi + Sphere.cy]       ; Utilise le CY de la sphère pointée !
    movss xmm4, xmm1                    ; Ny
    mulss xmm1, xmm1
    
    ; --- DISTANCE ---
    addss xmm0, xmm1
    
    ; --- TEST COLLISION ---
    ucomiss xmm0, [rdi + Sphere.r2]     ; Utilise le R² de la sphère pointée !
    jb .inside
    
    xor eax, eax                        ; Rien touché -> Return 0
    ret

.inside:
    ; --- CALCUL Z ---
    movss xmm2, [rdi + Sphere.r2]       ; Charge le rayon de la sphère
    subss xmm2, xmm0                    ; Z² = R² - Dist²
    sqrtss xmm2, xmm2                   ; Z
    
    ; --- CALCUL LUMIÈRE (Lambert) ---
    ; Note: Pour être parfait, INV_RADIUS devrait aussi être dans la struct
    ; car il dépend de la taille de la sphère. Ici on garde l'approx globale.
    
    movss xmm5, xmm3
    mulss xmm5, [rel INV_RADIUS]
    mulss xmm5, [rel LIGHT_X]
    
    movss xmm6, xmm4
    mulss xmm6, [rel INV_RADIUS]
    mulss xmm6, [rel LIGHT_Y]
    addss xmm5, xmm6
    
    movss xmm7, xmm2
    mulss xmm7, [rel INV_RADIUS]
    mulss xmm7, [rel LIGHT_Z]
    addss xmm5, xmm7
    
    ; Saturation basse (0)
    xorps xmm0, xmm0
    maxss xmm5, xmm0
    
    ; Conversion Couleur
    movss xmm0, [rel COLOR_SCALE]
    mulss xmm5, xmm0
    cvttss2si rax, xmm5
    
    ; Saturation haute (255)
    cmp rax, 255
    jle .ok
    mov rax, 255
.ok:
    ret