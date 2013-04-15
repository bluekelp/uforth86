
section .data
    banner: db 'uforth v0.0.3', 10
    banner_len: equ $-banner

    prompt_str: db 'ok', 10
    prompt_len: equ $-prompt_str

%define STACK_SIZE 1024

section .bss
    dstack: resd STACK_SIZE
    dsentinel: resd 1
    dsp: resd 1

section .text
    global _start

; void(void)
; ( -- , intialize stacks )
init:
    ; assign sentinel value to help to see if clobbered
    mov eax, 0badd00dh
    mov [dsentinel], eax

    ; compute top
    mov eax, dsentinel
    mov [dsp], eax
    ret

; ( -- , push a value (42) then pop it and leave value in <edx> )
test:
    mov edx, 42
    call _push
    mov edx, 0 ; reset to ensure we check popped value
    call _pop
    ret

; void(N:ecx, x:edx)
; ( -- x1 x2 xN pushes N values of x onto the Forth data stack )
_pushN:
push_n_loop:
    cmp ecx, 0
    je push_n_return
    call _push
    dec ecx
    jmp push_n_loop
push_n_return:
    ret

; void(n:edx)
; ( -- n, pushes edx onto the stack )
_push:
    mov eax, [dsp]
    dec eax
    dec eax
    dec eax
    dec eax
    mov [eax], edx
    mov [dsp], eax
    ret

; n:edx(void)
; ( n -- , pop a cell off stack )
_pop:
    mov eax, [dsp]
    mov edx, [eax]
    inc eax
    inc eax
    inc eax
    inc eax
    mov [dsp], eax
    ret

; uint:eax(void)
; ( -- , returns (eax) the size of the stack )
stack_size:
    pop ecx

    ; dsentinal - 4 bytes = top
    mov eax, dsentinel
    mov ebx, [dsp]
    sub eax, ebx
    shr eax, 2 ; divide by 4 to return #cells difference, not bytes

    jmp ecx ; popped above

; void( str:ecx, str_len:edx)
; ( -- , prints the string <str> to stdout )
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

_start:
_uforth:
    call init
    call print_banner

    call test
    mov ebx, edx ; return value = stack size
    mov eax, 1 ; sys_exit
    int 80h
