section .data
    banner: db 'uforth v0.0.1', 10
	banner_len: equ $-banner

    prompt_str: db 'ok', 10
    prompt_len: equ $-prompt_str

section .text
    global _start

print_banner:
    mov eax,4
    mov ebx,1
    mov ecx,banner
    mov edx,banner_len
    int 80h
    ret

prompt:
    mov eax,4
    mov ebx,1
    mov ecx,prompt_str
    mov edx,prompt_len
    int 80h
    ret

_start:
    call print_banner
    call prompt

	; exit w/0
    mov eax,1
    mov ebx,0
    int 80h
