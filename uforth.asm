
section .data
    banner: db 'uforth v0.0.5', 10
    banner_len: equ $-banner

    prompt_str: db 'ok', 10
    prompt_len: equ $-prompt_str

%define STACK_SIZE 1024

section .bss
    dstack: resd STACK_SIZE ; data-stack - no overflow detection
    dsentinel: resd 1 ; top of the stack - sentinel value to detect underflow
    dsp: resd 1 ; data-stack pointer (current stack head)

section .text
    global _start

; -----------------------------
;
; Forth primitives
;
; -----------------------------

; ( -- n, pushes <edx> into the stack as a cell )
_push:
    mov eax, [dsp]
    sub eax, 4
    mov [eax], edx
    mov [dsp], eax
    ret

; ( n -- , pop a cell off stack, leaves it in <edx> )
_pop:
    mov eax, [dsp]
    mov edx, [eax]
    add eax, 4
    mov [dsp], eax
    ret

; ( c -- , pops a cell and prints its first byte to stdout )
_emit:
    call _pop
    push edx
    mov ecx, esp ; ecx = string to write (_pop leaves in edx)
    mov edx, 1   ; # bytes to write
    mov eax, 4 ; sys_write
    mov ebx, 1 ; fd 1 = stdout
    int 80h
    pop edx
    ret

; -----------------------------
; 
; support functions
; 
; -----------------------------

; ( -- , intialize stacks )
init:
    ; assign sentinel value to help to see if clobbered
    mov eax, 0badd00dh
    mov [dsentinel], eax

    ; compute top
    mov eax, dsentinel
    mov [dsp], eax
    ret

; ( -- x1 x2 xN pushes <ecx> values of <x> onto the Forth data stack )
_pushN:
push_n_loop:
    cmp ecx, 0
    je push_n_return
    call _push
    dec ecx
    jmp push_n_loop
push_n_return:
    ret

; ( -- , returns the size of the stack in <eax> )
stack_size:
    pop ecx

    ; dsentinal - 4 bytes = top
    mov eax, dsentinel
    mov ebx, [dsp]
    sub eax, ebx
    shr eax, 2 ; divide by 4 to return #cells difference, not bytes

    jmp ecx ; popped above

; ( s l -- , prints <l> bytes of the string pointed to by <s> to stdout )
print:
    pop eax ; return location
    pop edx ; lengh
    pop ecx ; string location
    push eax ; return location
    mov eax, 4 ; sys_write
    mov ebx, 1 ; fd 1 = stdout
    int 80h
    ret

print_banner:
    push banner
    push banner_len
    call print
    ret

prompt:
    push prompt_str
    push prompt_len
    call print
    ret

test:
    mov edx, 65 ; 65 = ASCII capital A
    call _push
    call _emit
    ret

; -----------------------------
; 
; entry
; 
; -----------------------------

_start:
_uforth:
    call init
    call print_banner

    call test
    mov ebx, edx ; return value = stack size
    mov eax, 1 ; sys_exit
    int 80h
