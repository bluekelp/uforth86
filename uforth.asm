section .data
    s: db 'Hello, world!', 10
	slen: equ $-s

section .text
    global _start

_start:
	; write string to fd 1 (stdout)
    mov eax,4
    mov ebx,1
    mov ecx,s
    mov edx,slen
    int 80h

	; exit w/0
    mov eax,1
    mov ebx,0
    int 80h
