section .data
    banner: db 'uforth v0.0.3', 10
	banner_len: equ $-banner

    prompt_str: db 'ok', 10
    prompt_len: equ $-prompt_str

%define STACK_SIZE 10

section .bss
    dstack: resd STACK_SIZE
    dsentinel: resd 1
    dsp: resd 1

section .text
    global _start

init:
    ; assign sentinel value to help to see if clobbered
    mov eax, 0badd00dh
    mov [dsentinel], eax

    ; compute top
    mov eax, dsentinel
    mov [dsp], eax
    call _push ; need this once to compute top which is desntinal-1 cells
    ret

; push ecx values onto stack
_pushN:
    pop eax
    ; ecx assumed set by caller
push_n_loop:
    cmp ecx, 0
    je push_n_return
    call _push
    dec ecx
    jmp push_n_loop
push_n_return:
    jmp eax ; popped above

_push:
    mov eax, [dsp]
    dec eax
    dec eax
    dec eax
    dec eax
    mov [eax], edx
    mov [dsp], eax
    ret

stack_size:
    pop ecx

    ; dsentinal - 4 bytes = top
    mov eax, dsentinel
    dec eax
    dec eax
    dec eax
    dec eax

    mov ebx, [dsp]
    sub eax, ebx
    shr eax, 2 ; divide by 4 to return #cells difference, not bytes
    push eax

    jmp ecx ; popped above

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
    call init
    call print_banner
    call prompt

    call stack_size
    pop ebx ; return code
    mov eax, 1 ; sys_exit
    int 80h
