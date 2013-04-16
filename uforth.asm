
section .data
    banner: db 'uforth v0.0.6', 10
    banner_len: equ $-banner

    ok_str: db 'ok', 10
    ok_len: equ $-ok_str

    error_str: db 'error', 10
    error_len: equ $-error_str

    test_str: db 'abc 123  d'
    test_str_len: equ $-test_str

%define STACK_SIZE 1024
%define INPUT_BUFFER_SIZE 1024

section .bss
    dstack:     resd STACK_SIZE ; data-stack - no overflow detection
    dsentinel:  resd 1          ; top of the stack - sentinel value to detect underflow
    dsp:        resd 1          ; data-stack pointer (current stack head)
    h:          resd 1          ; H - end of dictionary
    input:      resb INPUT_BUFFER_SIZE
    input_p:    resd 1          ; pointer to current location in input

section .text
    global _start

%macro directcall 1
    ; nothing
%endmacro

%macro cprologue 1
    push ebp
    mov ebp, esp
    sub esp, %1
%endmacro

%macro creturn 0
    pop ebp
    ret
%endmacro

%macro @PUSH_EAX 0
    call _push_asm
%endmacro

%macro @POP_EAX 0
    call _pop_asm
%endmacro

%macro @EMIT 0
    call _emit_asm
%endmacro

%macro @TOKEN 0
    call _token_asm
%endmacro

%macro @NUMBER 0
    call _number_asm
%endmacro

; -----------------------------
;
; Forth primitives
;
; -----------------------------


; ( -- n, pushes <eax> into the stack as a cell )
PUSH_EAX:
db 8,'push_eax' ; #byte in name, name
dd 0            ; link pointer
dd _push_asm    ; code pointer
                ; param field empty - primitive assembly
_push_asm:
    directcall 4
    mov ebx, [dsp] ; load pointer
    sub ebx, 4     ; decrement (push)
    mov [ebx], eax ; store value
    mov [dsp], ebx ; update pointer
    ret

; ( n -- , pop a cell off stack, leaves it in <eax> )
POP_EAX:
db 7,'pop_eax'  ; #byte in name, name
dd PUSH_EAX     ; link pointer
dd _pop_asm     ; code pointer
                ; param field empty - primitive assembly
_pop_asm:
    directcall 4
    mov ebx, [dsp] ; load pointer
    mov eax, [ebx] ; fetch value            <-----
    add ebx, 4     ; increment (pop)
    mov [dsp], ebx ; update pointer
    ret

; ( c -- , pops a cell and prints its first byte to stdout )
EMIT:
db 4,'emit'     ; #byte in name, name
dd POP_EAX      ; link pointer
dd _emit_asm    ; code pointer
                ; param field empty - primitive assembly
_emit_asm:
    directcall 0
    @POP_EAX
    push eax
    mov ecx, esp ; ecx = pointer to string to write (need pointer to we use esp trick, not eax directly)
    mov edx, 1   ; # bytes to write
    mov eax, 4 ; sys_write
    mov ebx, 1 ; fd 1 = stdout
    int 80h
    pop eax
    ret

; x86 stack: ( s l -- )
; ( -- n , parses a decimal number from <s> of length <l> and pushes it on the stack )
; undefined if <l> less than 1
; <n> will by 10x too large if we encounter an ASCII char outside '0'..'9' but otherwise ok
NUMBER:
db 6,'number'   ; #byte in name, name
dd EMIT         ; link pointer
dd _number_asm  ; code pointer
                ; param field empty - primitive assembly
_number_asm:
    directcall 0
    pop eax
    pop ecx ; length
    pop edx ; string pointer
    push eax
    mov eax, 0
.numloop:
    imul eax, 10 ; ok to do when eax = 0 b/c 0*10 still = 0
    mov ebx, 0
    mov bl, [edx] ; bl = (char)*p
    cmp ebx, 30h ; '0'
    jl .badchar
    cmp ebx, 39h ; '9'
    jg .badchar
    sub ebx, 30h ; difference is decimal 0..9
    add eax, ebx
    ; check for last char
    cmp ecx, 1
    je .numexit
    ; prepare for next digit
    dec ecx
    inc edx
    jmp .numloop
.badchar:
.numexit:
    @PUSH_EAX ; uses eax - push result on data stack
    ret


; x86 stack: ( s l -- )
; ( -- n , parses a string and pushes the number of bytes in the next token )
TOKEN:
db 5,'token'    ; #byte in name, name
dd NUMBER       ; link pointer
dd _token_asm   ; code pointer
                ; param field empty - primitive assembly
_token_asm:
    ; TODO cleanup registers/use
    pop eax
    pop ecx
    pop ebx
    push eax
    mov edx, 0
.tokenloop:
    cmp ecx, 0
    je .tokenexit
    ; read byte and check if space/tab
    mov eax, 0
    mov al, [ebx]
    cmp al, 20h ; space (ASCII 32)
    je .tokenexit
    cmp al, 9h ; tab
    je .tokenexit
    ; prep for next char (if any)
    inc ebx
    inc edx
    dec ecx
    jmp .tokenloop
.tokenexit:
    mov eax, edx
    @PUSH_EAX
    ret

S0:
db 2,'s0'       ; #byte in name, name
dd TOKEN        ; link pointer
dd _S0_asm      ; code pointer
                ; param field empty - primitive assembly
_S0_asm:
    mov eax, dsentinel
    @PUSH_EAX
    ret

TICKS:
db 2,"'s"       ; #byte in name, name
dd S0           ; link pointer
dd _tickS_asm   ; code pointer
                ; param field empty - primitive assembly
_tickS_asm:
    mov eax, [dsp]
    @PUSH_EAX
    ret

H:
    dd 0,0,0,0 ; some nulls

; -----------------------------
; 
; support functions
; 
; -----------------------------

read_char:
    mov ecx, [input_p]  ; where to read
    mov edx, 1          ; # bytes to read
    mov eax, 3          ; sys_read
    mov ebx, 0          ; fd 0 = stdin
    int 80h
    cmp eax, 1          ; # bytes read
    je  .readcharok
.readerr:
    mov eax, 0
    ret
.readcharok:
    mov eax, [input_p]
    mov al,  [eax]
    add [input_p], DWORD 1  ; increment by a byte, not an int
    ret

read_line:
.readlineloop:
    mov eax, 0
    call read_char
    cmp eax, 0       ; error
    je .readlineerr
    cmp al, 10       ; newline
    je  .readlineok
    jmp .readlineloop
.readlineerr:
    call error
    ret
.readlineok:
    call ok
    ret

; ( -- , intialize stacks )
init:
    mov [dsentinel], DWORD 0badd00dh    ; assign sentinel value to help to see if clobbered
    mov [dsp], DWORD dsentinel          ; compute top of stack/S0
    mov [h], DWORD H                    ; set H
    mov [input_p], DWORD input
    ret

; ( -- x1 x2 xN pushes <ecx> values of <x> onto the Forth data stack )
_pushN:
.pushnloop:
    cmp ecx, 0
    je .pushnexit
    @PUSH_EAX
    dec ecx
    jmp .pushnloop
.pushnexit:
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

ok:
    push ok_str
    push ok_len
    call print
    ret

error:
    push error_str
    push error_len
    call print
    ret

test:
    call read_line
    mov eax, [input_p]
    sub eax, input
    push eax            ; length of buffer
    add eax, '0'        ; convert to ASCII digit
    @PUSH_EAX
    @EMIT

    mov eax, 10
    @PUSH_EAX
    @EMIT

    pop ebx             ; length of input buffer (including newline, if present)
    push input
    push ebx
    call print

    mov eax, '*'
    @PUSH_EAX
    @EMIT

    mov eax, test_str
    add eax, 0
    push eax
    mov eax, test_str_len
    sub eax, 0
    push eax
    @TOKEN
    @POP_EAX
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
    mov ebx, eax    ; return value of test is our exit code
    mov eax, 1      ; sys_exit
    int 80h
