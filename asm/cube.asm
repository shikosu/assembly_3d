BITS 64
global _start

section .data
    SYS_WRITE equ 1
    STDOUT equ 1
    WIDTH equ 256
    HEIGHT equ 256
    PIXEL_COUNT equ WIDTH * HEIGHT
    BUFFER_SIZE equ PIXEL_COUNT * 3
    
    ; --- GEOMETRIE ---
    FOCAL_LENGTH dd 200.0
    CAMERA_Z_OFFSET dd 3.5
    CENTER_X_FLOAT dd 128.0
    CENTER_Y_FLOAT dd 128.0

    ; --- ANIMATION ---
    current_angle dd 0.0
    angle_speed   dd 0.03
    cos_val       dd 0.0
    sin_val       dd 0.0

    ; --- CUBE VERTICES ---
    VERTEX_COUNT equ 8
    cube_vertices:
        dd -1.0, -1.0, -1.0
        dd  1.0, -1.0, -1.0
        dd  1.0,  1.0, -1.0
        dd -1.0,  1.0, -1.0
        dd -1.0, -1.0,  1.0
        dd  1.0, -1.0,  1.0
        dd  1.0,  1.0,  1.0
        dd -1.0,  1.0,  1.0

    ; --- CUBE EDGES ---
    EDGE_COUNT equ 12
    cube_edges:
        db 0,1, 1,2, 2,3, 3,0
        db 4,5, 5,6, 6,7, 7,4
        db 0,4, 1,5, 2,6, 3,7

section .bss
    pixel_buffer resb BUFFER_SIZE
    projected_coords resd 16 ; 32 bits

section .text
_start:
    lea r15, [rel pixel_buffer]

main_loop:

    ; 1. CLEAR SCREEN
    xor rax, rax
    mov rcx, BUFFER_SIZE / 8
    mov rdi, r15
    rep stosq

    ; 2. ROTATION
    movss xmm0, [rel current_angle]
    addss xmm0, [rel angle_speed]
    movss [rel current_angle], xmm0
    fld dword [rel current_angle]
    fsincos
    fstp dword [rel cos_val]
    fstp dword [rel sin_val]

    ; 3. PROJECTION
    xor rbx, rbx
    lea rsi, [rel cube_vertices]
    lea rdi, [rel projected_coords]

vertex_loop:
    cmp rbx, VERTEX_COUNT
    jge edges_loop_start

    ; Load & Rotate
    mov rax, rbx
    imul rax, 12
    movss xmm0, [rsi + rax]
    movss xmm1, [rsi + rax + 4]
    movss xmm2, [rsi + rax + 8]

    movss xmm3, xmm0
    movss xmm4, xmm2
    movss xmm0, xmm3
    mulss xmm0, [rel cos_val]
    movss xmm5, xmm4
    mulss xmm5, [rel sin_val]
    subss xmm0, xmm5
    movss xmm2, xmm3
    mulss xmm2, [rel sin_val]
    movss xmm5, xmm4
    mulss xmm5, [rel cos_val]
    addss xmm2, xmm5

    ; Project
    addss xmm2, [rel CAMERA_Z_OFFSET]
    mov rax, 0x3DCCCCCD
    movd xmm5, eax
    maxss xmm2, xmm5
    
    divss xmm0, xmm2
    divss xmm1, xmm2
    mulss xmm0, [rel FOCAL_LENGTH]
    mulss xmm1, [rel FOCAL_LENGTH]
    addss xmm0, [rel CENTER_X_FLOAT]
    addss xmm1, [rel CENTER_Y_FLOAT]

    ; Store (32 bits)
    cvttss2si r8d, xmm0
    cvttss2si r9d, xmm1
    
    mov rax, rbx
    shl rax, 3
    mov [rdi + rax], r8d
    mov [rdi + rax + 4], r9d

    inc rbx
    jmp vertex_loop

    ; 4. DRAW LINES
edges_loop_start:
    xor rbx, rbx
    lea rsi, [rel cube_edges]
    lea rdi, [rel projected_coords]

edges_loop:
    cmp rbx, EDGE_COUNT
    jge end_frame

    ; Index Load
    xor rax, rax1.0, -1.0, -1.0
    mov al, [rsi + rbx*2]
    xor rcx, rcx
    mov cl, [rsi + rbx*2 + 1]

    ; Load Coords (Sign Extend)
    shl rax, 3
    movsxd r8, dword [rdi + rax]    ; X0
    movsxd r9, dword [rdi + rax+4]  ; Y0
    
    shl rcx, 3
    movsxd r10, dword [rdi + rcx]   ; X1
    movsxd r11, dword [rdi + rcx+4] ; Y1

    push rbx
    push rsi
    push rdi
    call draw_line_simple
    pop rdi
    pop rsi
    pop rbx

    inc rbx
    jmp edges_loop

end_frame:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, r15
    mov rdx, BUFFER_SIZE
    syscall
    jmp main_loop

; ========================================================
; BRESENHAM SIMPLE (SANS INSTRUCTIONS COMPLEXES)
; ========================================================
draw_line_simple:
    ; --- CALCUL DX (ABS) ---
    mov rax, r10
    sub rax, r8     ; rax = x1 - x0
    cmp rax, 0      ; Est-ce négatif ?
    jge .dx_pos
    neg rax         ; Si oui, on rend positif
.dx_pos:            ; rax contient abs(dx)

    ; --- CALCUL SX ---
    mov rcx, 1      ; sx = 1
    cmp r8, r10
    jl .sx_done     ; Si x0 < x1, sx est bien 1
    mov rcx, -1     ; Sinon sx = -1
.sx_done:

    ; --- CALCUL DY (ABS & NEG) ---
    mov rdx, r11
    sub rdx, r9     ; rdx = y1 - y0
    cmp rdx, 0
    jge .dy_pos
    neg rdx
.dy_pos:            ; rdx contient abs(dy)
    neg rdx         ; rdx = -abs(dy) (On veut dy négatif pour l'algo)

    ; --- CALCUL SY ---
    mov rsi, 1      ; sy = 1
    cmp r9, r11
    jl .sy_done
    mov rsi, -1     ; sy = -1
.sy_done:

    ; --- ERROR ---
    mov rdi, rax    ; err = dx
    add rdi, rdx    ; err = dx + dy (dy est négatif)

    mov r12, 1000   ; Sécurité

.loop:
    dec r12
    jz .ret

    ; Bounds Check
    cmp r8, 0
    jl .skip_pixel
    cmp r8, WIDTH
    jge .skip_pixel
    cmp r9, 0
    jl .skip_pixel
    cmp r9, HEIGHT
    jge .skip_pixel

    ; Plot Pixel (Vert)
    imul rbx, r9, WIDTH
    add rbx, r8
    lea rbx, [rbx + rbx*2]
    add rbx, r15
    mov byte [rbx], 0
    mov byte [rbx+1], 255
    mov byte [rbx+2], 0

.skip_pixel:
    cmp r8, r10
    jne .calc_next
    cmp r9, r11
    je .ret

.calc_next:
    mov rbx, rdi
    add rbx, rbx    ; e2 = 2 * err
    
    cmp rbx, rdx
    jl .step_y
    add rdi, rdx    ; err += dy
    add r8, rcx     ; x0 += sx
    
.step_y:
    cmp rbx, rax
    jg .loop
    add rdi, rax    ; err += dx
    add r9, rsi     ; y0 += sy
    jmp .loop

.ret:
    ret