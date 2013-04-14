section .data
    banner: db 'uforth v0.0.1', 10
	banner_len: equ $-banner

    prompt_str: db 'ok', 10
    prompt_len: equ $-prompt_str

section .text
    global _start

print:
    pop eax ; return location
    pop edx ; lengh
    pop ecx ; string location
    push eax ; return location
    mov eax,4
    mov ebx,1
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
    call print_banner
    call prompt

    mov eax,1
    mov ebx,0
    int 80h
