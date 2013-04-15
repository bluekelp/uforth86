
section .data
    banner: db 'uforth v0.0.5', 10
    banner_len: equ $-banner

    prompt_str: db 'ok', 10
    prompt_len: equ $-prompt_str

    test_str: db 'abc 123  d'
    test_str_len: equ $-test_str

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

; x86 stack: ( s l -- )
; ( -- n , parses a decimal number from <s> of length <l> and pushes it on the stack )
; undefined if <l> less than 1
; <n> will by 10x too large if we encounter an ASCII char outside '0'..'9' but otherwise ok
_number:
    pop eax
    pop ecx ; length
    pop edx ; string pointer
    push eax
    mov eax, 0

number_loop:
    imul eax, 10 ; ok to do when eax = 0 b/c 0*10 still = 0
    mov ebx, 0
    mov bl, [edx] ; bl = (char)*p
    cmp ebx, 30h ; '0'
    jl bad_char
    cmp ebx, 39h ; '9'
    jg bad_char
    sub ebx, 30h ; difference is decimal 0..9
    add eax, ebx

    cmp ecx, 1
    je number_done

    ; prepare for next digit
    dec ecx
    inc edx
    jmp number_loop

bad_char:
    ;push edx
    ;mov edx,0
    ;idiv 10 ; undo and *try* to have correct result

number_done:
    mov edx, eax ; _push expects value in <edx>
    call _push

    ret


; x86 stack: ( s l -- )
; ( -- n , parses a string and pushes the number of bytes in the next token )
_token:
    pop eax
    pop ecx
    pop ebx
    push eax

    mov edx, 0
token_loop:
    cmp ecx, 0
    je token_loop_done

    ; read byte and check if space/tab
    mov eax, 0
    mov al, [ebx]
    cmp al, 20h ; space (ASCII 32)
    je token_loop_done
    cmp al, 9h ; tab
    je token_loop_done

    ; prep for next char (if any)
    inc ebx
    inc edx
    dec ecx
    jmp token_loop

token_loop_done:
    call _push ; expects N in <edx>
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

; x86 stack: ( s l -- , prints <l> bytes of the string pointed to by <s> to stdout )
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
    mov eax, test_str
    add eax, 3
    push eax
    push test_str_len
    call _token
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
    mov ebx, edx
    mov eax, 1 ; sys_exit
    int 80h
