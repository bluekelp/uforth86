
%define TAB     9
%define SPACE   ' '         ; ASCII 20h
%define CR      13
%define NEWLINE 10
%define NL      NEWLINE
%define ENTER   NEWLINE

%define cstr(x) db x, 0

section .data
    banner_str: cstr('uforth v0.0.6')
    ok_str:     cstr('ok ')
    error_str:  cstr('error ')
    word_not_found_str: cstr('word not found: ')
    null_str:   cstr('')
    test_str:   cstr('test')
%ifidn __OUTPUT_FORMAT__, macho32
    eol_str:    db CR, NL, 0
%else
    eol_str:    db NL, 0
%endif

%define STACK_SIZE      128
%define INPUT_BUFSIZE   128
%define SCRATCH_BUFSIZE 128

section .bss
    dstack:         resd STACK_SIZE         ; data-stack - no overflow detection
    dsentinel:      resd 1                  ; top of the stack - sentinel value to detect underflow
    dsp:            resd 1                  ; data-stack pointer (current stack head)
    h:              resd 1                  ; H - end of dictionary
    input:          resb INPUT_BUFSIZE
    input_p:        resd 1                  ; pointer to current location in input
    tokenp:         resd 1                  ; misc pointer to use
    scratch:        resb SCRATCH_BUFSIZE    ; tmp buffer to use
    scratchp:       resd 1                  ; tmp int to use
    eof:            resb 1                  ; set to true when EOF detected
    dict:           resd 1                  ; pointer to start of dictionary list

%ifidn __OUTPUT_FORMAT__, macho32
%define __ASM_MAIN start
%else
%define __ASM_MAIN _start
%endif

section .text
    global __ASM_MAIN

%macro directcall 1
    ; nothing
%endmacro

;;

%define __cdecl             ; used to annotate a route uses c calling convention

%define __cdecl_hybrid      ; used to annotate a route uses c calling convention - modified
                            ; in that no params to routine are pushed on stack. parameters are
                            ; expected in eax, ebx, ecx, and/or edx

%macro C_prologue 1
    push ebp
    mov  ebp, esp
    sub  esp, %1
    push edi
    push esi
%endmacro

%macro C_epilogue 0
    pop  esi
    pop  edi
    mov  esp, ebp
    pop  ebp
    ret
%endmacro

; -- macros to help access local vars and params
;    only full sized ints are supported
%macro C_local 1            ; index-1 based local parameter (e.g., C_local(1) is our first local
    ebp-(%1*4)
%endmacro

%macro C_param 1
    ebp+(4+(%1*4))          ; index-1 based parameter to routine (e.g., C_param(1) = first param)
                            ; C_param(0) is undefined
%endmacro

;;

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

%macro @CR 0
    push eax
    mov  eax, eol_str
    call _putstr
    pop  eax
%endmacro

%macro putc 1
    mov  eax, %1
    @PUSH_EAX
    @EMIT
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
%ifidn __OUTPUT_FORMAT__, macho32
    ; OSX
    directcall 0
    @POP_EAX
    push eax

    push 1            ; length
    push eax            ; str
    push 1              ; fd
    mov  eax, 4
    sub  esp, 4         ; extra space
    int  80h
    add  esp, 16
    pop  eax
    ret
%else
    ; Linux
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
%endif


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
    jb   .badchar
    cmp  ebx, '9'
    ja   .badchar
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


; parses a string (<eax>) and pushes the number of bytes in the first token onto the Forth stack
; <eax> returned is also token length
TOKEN:
db 5,'token'                ; #byte in name, name
dd NUMBER                   ; link pointer
dd _token_asm               ; code pointer
                            ; param field empty - primitive assembly
_token_asm:
    pop  ebx                ; return value
    call _strtok
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
    call forth_stack_depth
    @PUSH_EAX
    ret

H:
db 1,"h    "                ; #byte in name, name
dd DEPTH                    ; link pointer
dd _h_asm                   ; code pointer
                            ; param field empty - primitive assembly
_h_asm:
    mov eax, [dict]
    @PUSH_EAX
    ret

; -----------------------------
;
; c string functions
;
; -----------------------------

; prints the c string pointed to by <eax> to stdout
; returns: void - <eax> undefined
_putstr:
%ifidn __OUTPUT_FORMAT__, macho32
    ; OSX
    push eax                ; save string base for later math
    call _strlen            ; length now in eax
    pop  ebx                ; str
    push eax                ; length
    push ebx                ; str
    push 1                  ; fd
    mov  eax, 4
    sub  esp, 4             ; extra space for assumed sys_call function
    int  80h
    add  esp, 16
    ret
%else
    ; Linux
    push eax                ; save string base for later math
    call _strlen            ; length now in eax
    mov  edx, eax           ; edx = length
    pop  ecx                ; base string location (for len math)
    mov  eax, 4             ; sys_write
    mov  ebx, 1             ; fd 1 = stdout
    int  80h
    ret

%endif

; prints the c string pointed to by <eax> to stdout, followed by (platform specific) EOL suffix
; returns: void - <eax> undefined
_puts:
    call _putstr
    @CR
    ret

; string pointer in <eax>, return string length in <eax>
_strlen:
    push eax
.strlenloop:
    cmp  [eax], byte 0
    je   .strlenexit
    inc  eax
    jmp  .strlenloop
.strlenexit:
    pop  ebx
    sub  eax, ebx           ; <eax> now has strlen (current-original)
    ret

; parse string pointed to by <eax> and return # chars in its first token in <eax>
; writes a null in the string at the boundary of the token (the terminating space/tab)
_strtok:
    push eax                ; original pointer
    mov  ebx, eax
.strtokloop:
    ; read byte and check if space/tab
    mov  eax, 0
    mov  al, [ebx]
    ; compare to terminators
    cmp  al, 0
    je   .strtokexit
    cmp  al, SPACE
    je   .strtokexit
    cmp  al, TAB
    je   .strtokexit
    ; prep for next char (if any)
    inc  ebx
    jmp  .strtokloop
.strtokexit:
    mov  [ebx], BYTE 0      ; overwrite SPACE/TAB with null
    mov  eax, ebx
    pop  ebx                ; original pointer
    sub  eax, ebx           ; length
    ret

; copies string <ebx> into string <eax> (like strcpy(eax, ebx))
_strcpy:
.strcpyloop:
    mov  ecx, 0
    mov  cl, [ebx]
    mov  [eax], cl
    inc  eax
    inc  ebx
    cmp  cl, 0              ; compare after copy to ensure null terminated
    jne  .strcpyloop
    ret

; reverse chars in the string <eax>
_strrev:
    push eax
    push eax
    call _strlen
    pop  ebx
    add  ebx, eax
    dec  ebx                ; string + strlen() - 1  // -1 is b/c reverse_bytes's 2nd pointer is inclusive
    pop  eax                ; string
    cmp  eax, ebx
    jae  .strrevexit        ; exit w/o reversing if start >= stop (check b/c of the strlen()-1 above on 1 byte strings, etc.)
    call reverse_bytes
.strrevexit:
    ret

; compares <eax> to <ebx>;  returns -1 if string eax < ebx, 0 if same, 1 if ebx > eax
; eax and ebx must not be same
_strcmp:
    mov  ecx, 0
    call _strcmpx
    ret

; _strcmpi ; uppercase chars are 20h lower than lower case in ASCII
; eax and ebx must not be same
_strcmpi:
    mov  ecx, 1
    call _strcmpx
    ret

; compares <eax> to <ebx>;  returns -1 if string eax < ebx, 0 if same, 1 if ebx > eax
; eax and ebx must not be same
_strcmpx:
.strcmpxloop:
    mov  dl, [eax]
    mov  dh, [ebx]
    inc  eax
    inc  ebx
    cmp  dl, 0
    je   .strcmpxadone
    cmp  dl, 0
    je   .strcmpxbdone
    cmp  ecx, 0             ; check if case insensitive compare
    jz   .strcmpxcompare
    cmp  dl, 41h            ; convert to lowercase, as necessary
    jb   .firstdone
    cmp  dl, 5ah
    ja   .firstdone
    or   dl, 20h
.firstdone:
    cmp  dh, 41h
    jb   .seconddone
    cmp  dh, 5ah
    ja   .seconddone
    or   dh, 20h
.seconddone:
.strcmpxcompare:
    cmp  dl, dh             ; <--- compare
    jb   .strcmpxaless
    ja   .strcmpxbless
    jmp  .strcmpxloop

.strcmpxadone:
    cmp  dh, 0
    je   .strcmpxsame
.strcmpxaless:
    mov  eax, -1
    ret
.strcmpxbdone:
    cmp  dl, 0
    je   .strcmpxsame
.strcmpxbless:
    mov  eax, 1
    ret
.strcmpxsame:
    mov  eax, 0
    ret


; -----------------------------
;
; support functions
;
; -----------------------------

; writes eax as unsigned decimal string to <scratch> and return length in eax
_itoa:
    ; eax = number to convert
    mov  [scratchp], DWORD scratch    ; scratchp = &scratch
    mov  ecx, [scratchp]    ; ecx = scratchp
    mov  ebx, 10            ; radix
._itoaloop:
    mov  edx, 0             ; upper portion of number to divide - set to 0 to just use eax
    idiv ebx                ; divides eax by ebx
    ; edx=remainder eax=quotient
    add  edx, '0'           ; convert to ASCII char
    mov  [ecx], dl          ; (char*)*scratchp = (byte)edx
    inc  ecx
    cmp  eax, 0
    jne  ._itoaloop          ; next char if more (if eax > ebx (radix))
._itoaexit:
    mov  [scratchp], ecx    ; scratchp = ecx (stores all increments)
    ; reverse bytes in scratch
    mov  eax, ecx           ; eax = ecx = scratchp
    sub  eax, scratch       ; length of string in scratch
    push eax                ; length of scratch string
    mov  eax, scratch       ; addr of first char
    mov  ebx, [scratchp]
    dec  ebx                ; addr of last char
    call reverse_bytes
    pop  eax                ; length of string
    ret

; eax - pointer to start of buffer
; ebx - pointer to   end of buffer (inclusive)
reverse_bytes:
.reverseloop:
    cmp  eax, ebx           ; src <= dest?
    jae  .reverseexit       ; jae = unsigned, jge = signed
    mov  cl, [eax]          ; cl = *src
    mov  ch, [ebx]          ; ch = *dest
    mov  [eax], ch          ; *src = ch
    mov  [ebx], cl          ; *dest = cl
    inc  eax                ; src++
    dec  ebx                ; dest--
    jmp  .reverseloop
.reverseexit:
    ret

; waits for a char from stdin and stores in current location of [input_p].
; increments <input_p> one byte when complete
; return 0 on error/EOF or ASCII value of char read otherwise
_getc:
%ifidn __OUTPUT_FORMAT__, macho32
    ; OSX
    mov  ecx, [input_p]     ; where to read
	push 1					; buffer len/read len
	push ecx				; buffer ptr
	push 0					; fd 0 = stdin
	mov  eax, 3				; sys_read
    sub  esp, 4				; extra room
    int  80h
	add  esp, 16
%else
    ; Linux
    mov  ecx, [input_p]     ; where to read
    mov  edx, 1             ; # bytes to read
    mov  eax, 3             ; sys_read
    mov  ebx, 0             ; fd 0 = stdin
    int  80h
%endif
    cmp  eax, 0             ; # bytes read
    ja   .getcok
    je   .geteof
.getcerr:
    mov  eax, -1
    ret
.geteof:
    mov  eax, 0
    ret
.getcok:
    mov  eax, [input_p]
    mov  al,  [eax]
    add  [input_p], DWORD 1 ; increment by a byte (1), not an int (4)
    ret

; read a line of input (until either ENTER inputed or EOF/error)
; data are left in <input> buffer, location in buffer is dependent on
; value of <input_p> when this fx is called
; no return value
_gets:
.getsloop:
    mov eax, 0
    call _getc
    cmp  al, ENTER
    je   .getsenter
    cmp  eax, 0             ; EOF
    je   .getseof
    jl   .getserr           ; other error
    jmp  .getsloop
.getseof:
    mov [eof], BYTE 1
    jmp .getsok
.getserr:
    call error
    ret
.getsenter:
    mov  eax, [input_p]
    dec  eax                ; backup to NEWLINE
    mov  [eax], BYTE 0      ; make sure null terminated instead of NEWLINE
.getsok:
    ret

; init globals
init:
    mov  [dsentinel], DWORD 0badd00dh   ; assign sentinel value to help to see if clobbered
    mov  [dsp], DWORD dsentinel         ; compute top of stack/S0
    mov  [h], DWORD H                   ; set H
    mov  [input_p], DWORD input
    mov  [eof], BYTE 0                  ; seen EOF on input?
    mov  [dict], DWORD H                ; start of our dictionary - the last primitive Forth word defined
    ret

; ( -- , returns the depth of the Forth stack in <eax> )
forth_stack_depth:
    ; dsentinal - 4 bytes = top
    mov  eax, dsentinel
    mov  ebx, [dsp]
    sub  eax, ebx
    shr  eax, 2             ; divide by 4 to return #cells difference, not bytes
    ret

banner:
    mov  eax, banner_str
    call _puts
    ret

ok:
    mov  eax, ok_str
    call _putstr
    ret

error:
    mov  eax, error_str
    call _putstr
    ret

; exits app with return code of eax (lower byte)
_exit:
    mov  ebx, eax
    mov  eax, 1             ; sys_exit
    int  80h

; return 0 if string <eax> found in dictionary
__cdecl_hybrid
find:
    C_prologue(8)
    mov  ebx, test_str
    call _strcmpi
    C_epilogue
    ret

; execute a word
; eax holds pointer to string of word (name) to execute
execute:
    push eax
    call find
    cmp  eax, 0
    jne  .executenotfound
    ; else found - execute word
.executeexit:
    pop  eax
    mov  eax, 0
    ret
.executenotfound:
    mov  eax, word_not_found_str
    call _putstr
    pop  eax
    call _puts
    mov  eax, -1
    ret

; Forth's quit - outer loop that calls INTERPRET
quit:
    mov  [input_p], DWORD input
    call _gets              ; leaves string in [input]
    cmp  [eof], BYTE 0
    jne  .quitexit
    mov  eax, input
    call interpret
    call ok
    @CR
    jmp  quit
.quitexit:
    ret

; handle input/words found in <eax> pointer
interpret:
    mov  [tokenp], eax      ; token walker (TODO move pointer to be local to this function)
.interpretloop:
    call _strtok

    push eax                ; token size
    mov  eax, [tokenp]
    call execute
    ; TODO honor return code
    pop  ecx                ; token size

    mov  eax, [tokenp]
    add  eax, ecx
    inc  eax
    mov  [tokenp], eax
    mov  ebx, [input_p]
    cmp  eax, ebx
    jae  .interpretloopexit ; at/past last token
    jmp  .interpretloop
.interpretloopexit:
    mov  eax, 0
    ret

; -----------------------------
;
; entry
;
; -----------------------------

__ASM_MAIN:
_uforth:
    call init
    call banner
    call quit               ; main loop does not "quit" the app - is Forth's quit word
    call _exit              ; use whatever is in eax currently
