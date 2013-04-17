
%define TAB     9
%define SPACE   ' '         ; ASCII 20h
%define CR      13
%define NEWLINE 10
%define NL      NEWLINE
%define ENTER   NEWLINE

section .data
    banner:         db 'uforth v0.0.6', NL
    banner_len:     equ $-banner

    ok_str:         db 'ok', NL
    ok_len:         equ $-ok_str

    error_str:      db 'error', NL
    error_len:      equ $-error_str

%define STACK_SIZE 1024
%define INPUT_BUFSIZE 1024
%define SCRATCH_BUFSIZE 128

section .bss
    dstack:         resd STACK_SIZE         ; data-stack - no overflow detection
    dsentinel:      resd 1                  ; top of the stack - sentinel value to detect underflow
    dsp:            resd 1                  ; data-stack pointer (current stack head)
    h:              resd 1                  ; H - end of dictionary
    input:          resb INPUT_BUFSIZE
    input_p:        resd 1                  ; pointer to current location in input
    scratch:        resb SCRATCH_BUFSIZE    ; tmp buffer to use
    scratchp:       resd 1                  ; tmp int to use

section .text
    global _start

%macro directcall 1
    ; nothing
%endmacro

%macro cprologue 1
    push ebp
    mov  ebp, esp
    sub  esp, %1
%endmacro

%macro creturn 0
    pop  ebp
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
; Forth primitive words, with dictionary headers
;
; -----------------------------


; ( -- n, pushes <eax> into the stack as a cell )
PUSH_EAX:
db 8,'push_eax'             ; #byte in name, name
dd 0                        ; link pointer
dd _push_asm                ; code pointer
                            ; param field empty - primitive assembly
_push_asm:
    directcall 4
    mov  ebx, [dsp]         ; load pointer
    sub  ebx, 4             ; decrement (push)
    mov  [ebx], eax         ; store value
    mov  [dsp], ebx         ; update pointer
    ret

; ( n -- , pop a cell off stack, leaves it in <eax> )
POP_EAX:
db 7,'pop_eax'              ; #byte in name, name
dd PUSH_EAX                 ; link pointer
dd _pop_asm                 ; code pointer
                            ; param field empty - primitive assembly
_pop_asm:
    directcall 4
    mov  ebx, [dsp]         ; load pointer
    mov  eax, [ebx] ; <---- ; fetch value
    add  ebx, 4             ; increment (pop)
    mov  [dsp], ebx         ; update pointer
    ret

; ( c -- , pops a cell and prints its first byte to stdout )
EMIT:
db 4,'emit'                 ; #byte in name, name
dd POP_EAX                  ; link pointer
dd _emit_asm                ; code pointer
                            ; param field empty - primitive assembly
_emit_asm:
    directcall 0
    @POP_EAX
    push eax
    mov  ecx, esp           ; ecx = ptr to str to write (need ptr so we use esp trick, not eax directly)
    mov  edx, 1             ; # bytes to write
    mov  eax, 4             ; sys_write
    mov  ebx, 1             ; fd 1 = stdout
    int  80h
    pop  eax
    ret

; x86 stack: ( s l -- )
; ( -- n , parses a decimal number from <s> of length <l> and pushes it on the stack )
; undefined if <l> less than 1
; <n> will by 10x too large if we encounter an ASCII char outside '0'..'9' but otherwise ok
NUMBER:
db 6,'number'               ; #byte in name, name
dd EMIT                     ; link pointer
dd _number_asm              ; code pointer
                            ; param field empty - primitive assembly
_number_asm:
    directcall 0
    pop  eax
    pop  ecx                ; length
    pop  edx                ; string pointer
    push eax
    mov  eax, 0
.numloop:
    imul eax, 10            ; 10 = base; ok to do when eax = 0 b/c 0*10 still = 0
    mov  ebx, 0
    mov  bl, [edx]          ; bl = (char)*p
    cmp  ebx, '0'
    jl   .badchar
    cmp  ebx, '9'
    jg   .badchar
    sub  ebx, '0'           ; difference is decimal 0..9
    add  eax, ebx
    cmp  ecx, 1
    ; check for last char
    je   .numexit
    ; prepare for next digit
    dec  ecx
    inc  edx
    jmp  .numloop
.badchar:
.numexit:
    @PUSH_EAX               ; uses eax - push result on data stack
    ret


; x86 stack: ( s l -- )
; ( -- n , parses a string and pushes the number of bytes in the next token )
TOKEN:
db 5,'token'                ; #byte in name, name
dd NUMBER                   ; link pointer
dd _token_asm               ; code pointer
                            ; param field empty - primitive assembly
_token_asm:
    ; TODO cleanup registers/use
    pop  eax
    pop  ecx
    pop  ebx
    push eax
    mov  edx, 0
.tokenloop:
    cmp  ecx, 0
    je   .tokenexit
    ; read byte and check if space/tab
    mov  eax, 0
    mov  al, [ebx]
    cmp  al, SPACE
    je   .tokenexit
    cmp  al, TAB
    je   .tokenexit
    ; prep for next char (if any)
    inc  ebx
    inc  edx
    dec  ecx
    jmp  .tokenloop
.tokenexit:
    mov  eax, edx
    @PUSH_EAX
    ret

S0:
db 2,'s0'                   ; #byte in name, name
dd TOKEN                    ; link pointer
dd _S0_asm                  ; code pointer
                            ; param field empty - primitive assembly
_S0_asm:
    mov  eax, dsentinel
    @PUSH_EAX
    ret

TICKS:
db 2,"'s"                   ; #byte in name, name
dd S0                       ; link pointer
dd _tickS_asm               ; code pointer
                            ; param field empty - primitive assembly
_tickS_asm:
    mov  eax, [dsp]
    @PUSH_EAX
    ret

DEPTH:
db 5,"depth"                ; #byte in name, name
dd TICKS                    ; link pointer
dd _depth_asm               ; code pointer
                            ; param field empty - primitive assembly
_depth_asm:
    call stack_depth
    @PUSH_EAX
    ret

H:
    dd 0,0,0,0              ; some nulls

; -----------------------------
; 
; support functions
; 
; -----------------------------

; writes eax as unsigned decimal string to <scratch> and return length in eax
itoa:
    ; eax = number to convert
    mov  [scratchp], DWORD scratch    ; scratchp = &scratch
    mov  ecx, [scratchp]    ; ecx = scratchp
    mov  ebx, 10            ; radix
.itoaloop:
    mov  edx, 0             ; upper portion of number to divide - set to 0 to just use eax
    idiv ebx                ; divides eax by ebx
    ; edx=remainder eax=quotient
    add  edx, '0'           ; convert to ASCII char
    mov  [ecx], dl          ; (char*)*scratchp = (byte)edx
    inc  ecx
    cmp  eax, 0
    jne  .itoaloop          ; next char if more (if eax > ebx (radix))
.itoaexit:
    mov  [scratchp], ecx    ; scratchp = ecx (stores all increments)
    ; reverse bytes in scratch
    mov  eax, ecx           ; eax = ecx = scratchp
    sub  eax, scratch       ; length of string in scratch
    push eax                ; length of scratch string
    mov  ebx, scratch       ; addr of first char
    mov  ecx, [scratchp]
    dec  ecx                ; addr of last char
    call reverse_bytes
    pop  eax                ; length of string
    ret

; ebx - pointer to start of buffer
; ecx - pointer to   end of buffer (inclusive)
reverse_bytes:
.reverseloop:
    cmp  ebx, ecx           ; src <= dest?
    jae  .reverseexit       ; jae = unsigned, jge = signed
    mov  al, [ebx]          ; al = *src
    mov  dl, [ecx]          ; dl = *dest
    mov  [ebx], dl          ; *src = dl
    mov  [ecx], al          ; *dest = al
    inc  ebx                ; src++
    dec  ecx                ; dest--
    jmp  .reverseloop
.reverseexit:
    ret

; waits for a char from stdin and stores in current location of [input_p].
; increments <input_p> one byte when complete
; return 0 on error/EOF or ASCII value of char read otherwise
read_char:
    mov  ecx, [input_p]     ; where to read
    mov  edx, 1             ; # bytes to read
    mov  eax, 3             ; sys_read
    mov  ebx, 0             ; fd 0 = stdin
    int  80h
    cmp  eax, 1             ; # bytes read
    je   .readcharok
.readerr:
    mov  eax, 0
    ret
.readcharok:
    mov  eax, [input_p]
    mov  al,  [eax]
    add  [input_p], DWORD 1 ; increment by a byte, not an int
    ret

; read a line of input (until either ENTER inputed or EOF/error)
; data are left in <input> buffer, location in buffer is dependent on
; value of <input_p> when this fx is called
; no return value
read_string:
read_line:
.readlineloop:
    mov eax, 0
    call read_char
    cmp  eax, 0             ; error
    je   .readlineerr
    cmp  al, ENTER
    je   .readlineok
    jmp  .readlineloop
.readlineerr:
    call error
    ret
.readlineok:
    call ok
    ret

; init globals
init:
    mov  [dsentinel], DWORD 0badd00dh    ; assign sentinel value to help to see if clobbered
    mov  [dsp], DWORD dsentinel          ; compute top of stack/S0
    mov  [h], DWORD H                    ; set H
    mov  [input_p], DWORD input
    ret

; ( -- x1 x2 xN pushes <ecx> values of <eax> onto the Forth data stack )
_pushN:
.pushnloop:
    cmp  ecx, 0
    je   .pushnexit
    @PUSH_EAX
    dec  ecx
    jmp  .pushnloop
.pushnexit:
    ret

; ( -- , returns the depth of the stack in <eax> )
stack_depth:
    ; dsentinal - 4 bytes = top
    mov  eax, dsentinel
    mov  ebx, [dsp]
    sub  eax, ebx
    shr  eax, 2             ; divide by 4 to return #cells difference, not bytes
    ret

; x86 stack: ( s l -- , prints <l> bytes of the string pointed to by <s> to stdout )
print:
    pop  eax                ; return location
    pop  edx                ; lengh
    pop  ecx                ; string location
    push eax                ; return location
    mov  eax, 4             ; sys_write
    mov  ebx, 1             ; fd 1 = stdout
    int  80h
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
    mov  eax, [input_p]
    sub  eax, input         ; length of input in eax
    push eax                ; popped (below) for exit code

    call itoa               ; puts result in scratch

    push scratch
    push eax                ; length of scratch (left from itoa() call)
    call print

    mov  eax, NEWLINE
    @PUSH_EAX
    @EMIT

    pop  eax                ; length of input buffer (including newline, if present)
    push input
    push eax
    call print

    mov  eax, '*'
    @PUSH_EAX
    @EMIT

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
    mov  ebx, eax           ; return value of test is our exit code
    mov  eax, 1             ; sys_exit
    int  80h
