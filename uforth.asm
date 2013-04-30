
%define TAB     9
%define SPACE   ' '                         ; ASCII 20h
%define CR      13
%define NEWLINE 10
%define NL      NEWLINE
%define ENTER   NEWLINE
%define NULL    0

%define cstr(x) db x, 0

%define __cdecl             ; used to annotate a routine uses c calling convention

%define __cdecl_hybrid      ; used to annotate a routine uses a *modified* c calling convention
                            ; no params to routine are pushed on stack. parameters are
                            ; expected in eax, ebx, ecx, and/or edx.
                            ; simplifies caller too b/c no need to adjust/pop params from stack after

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

; index-1 based local parameter (e.g., C_local(1) is our first local
%define C_local(x) [ebp-(x*4)]

; index-1 based parameter to routine (e.g., C_param(1) = first param)
; C_param(0) is undefined
%define C_param(x)  [ebp+(4+(x*4))]

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
    push eax
    push ebx
    push ecx
    mov  eax, %1
    @PUSH_EAX
    @EMIT
    pop  ecx
    pop  ebx
    pop  eax
%endmacro


;; ---------- 


section .data
    banner_str: cstr('uforth v0.9.0')
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
    dict:           resd 1                  ; pointer to start of dictionary list (H)
    input:          resb INPUT_BUFSIZE
    input_p:        resd 1                  ; pointer to current location in input
    tokenp:         resd 1                  ; misc pointer to use
    scratch:        resb SCRATCH_BUFSIZE    ; tmp buffer to use
    scratchp:       resd 1                  ; tmp int to use
    eof:            resb 1                  ; set to true when EOF detected

%ifidn __OUTPUT_FORMAT__, macho32
%define __ASM_MAIN start
%else
%define __ASM_MAIN _start
%endif

section .text
    global __ASM_MAIN

; -----------------------------
;
; entry
;
; -----------------------------

__ASM_MAIN:
_uforth:
    call init
    call banner
    call quit               ; main loop of Forth; does not "quit" the app
    call _exit              ; use whatever is in eax currently



; -----------------------------
;
; Forth primitive words, with dictionary headers
;
; -----------------------------

; DICT_ENTRY name_cstr, nextDictEntry, code_ptr
%macro DICT_ENTRY 3
    cstr(%1)                ; name (null terminated)
    dd  %2                  ; next dict ptr
    dd  %3                  ; code ptr
    dd  0                   ; param ptr
%endmacro

; ( -- n, pushes <eax> into the stack as a cell )
PUSH_EAX:
DICT_ENTRY 'push_eax', NULL, _push_asm
_push_asm:
    mov  ebx, [dsp]         ; load pointer
    sub  ebx, 4             ; decrement (push)
    mov  [ebx], eax         ; store value
    mov  [dsp], ebx         ; update pointer
    ret

; ( n -- , pop a cell off stack, leaves it in <eax> )
POP_EAX:
DICT_ENTRY 'pop_eax', PUSH_EAX, _pop_asm
_pop_asm:
    mov  ebx, [dsp]         ; load pointer
    mov  eax, [ebx] ; <---- ; fetch value
    add  ebx, 4             ; increment (pop)
    mov  [dsp], ebx         ; update pointer
    ret

; ( c -- , pops a cell and prints its first byte to stdout )
EMIT:
DICT_ENTRY 'emit', POP_EAX, _emit_asm
_emit_asm:
%ifidn __OUTPUT_FORMAT__, macho32
    ; OSX
    @POP_EAX
    push eax
    mov  ecx, esp

    push 1                  ; length
    push ecx                ; str ptr of "push eax" above
    push 1                  ; fd
    mov  eax, 4
    sub  esp, 4             ; extra space
    int  80h
    add  esp, 16            ; the 16 we push - excluding extra space
    pop  eax
    ret
%else
    ; Linux
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
DICT_ENTRY 'number', EMIT, _number_asm
_number_asm:
    pop  eax
    pop  ecx                ; length
    pop  edx                ; string pointer
    push eax
    mov  eax, 0
.loop:
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
    je   .exit
    ; prepare for next digit
    dec  ecx
    inc  edx
    jmp  .loop
.badchar:
.exit:
    @PUSH_EAX               ; uses eax - push result on data stack
    ret


; parses a string (<eax>) and pushes the number of bytes in the first token onto the Forth stack
; <eax> returned is also token length
TOKEN:
DICT_ENTRY 'token', NUMBER, _token_asm
_token_asm:
    pop  ebx                ; return value
    call _strtok
    @PUSH_EAX
    ret

S0:
DICT_ENTRY 's0', TOKEN, _s0_asm
_s0_asm:
    mov  eax, dsentinel
    @PUSH_EAX
    ret

TICKS:
DICT_ENTRY "'s", S0, _tickS_asm
_tickS_asm:
    mov  eax, [dsp]
    @PUSH_EAX
    ret

DEPTH:
DICT_ENTRY 'depth', TICKS, _depth_asm
_depth_asm:
    call forth_stack_depth
    @PUSH_EAX
    ret

H:
DICT_ENTRY 'h', DEPTH, _h_asm
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
.loop:
    cmp  [eax], byte 0
    je   .exit
    inc  eax
    jmp  .loop
.exit:
    pop  ebx
    sub  eax, ebx           ; <eax> now has strlen (current-original)
    ret

; parse string pointed to by <eax> and return # chars in its first token in <eax>
; writes a null in the string at the boundary of the token (the terminating space/tab)
_strtok:
    push eax                ; original pointer
    mov  ebx, eax
.loop:
    ; read byte and check if space/tab
    mov  eax, 0
    mov  al, [ebx]
    ; compare to terminators
    cmp  al, 0
    je   .exit
    cmp  al, SPACE
    je   .exit
    cmp  al, TAB
    je   .exit
    ; prep for next char (if any)
    inc  ebx
    jmp  .loop
.exit:
    mov  [ebx], BYTE 0      ; overwrite SPACE/TAB with null
    mov  eax, ebx
    pop  ebx                ; original pointer
    sub  eax, ebx           ; length
    ret

; copies string <ebx> into string <eax> (like strcpy(eax, ebx))
_strcpy:
.loop:
    mov  ecx, 0
    mov  cl, [ebx]
    mov  [eax], cl
    inc  eax
    inc  ebx
    cmp  cl, 0              ; compare after copy to ensure null terminated
    jne  .loop
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
    jae  .exit              ; exit w/o reversing if start >= stop (check b/c of the strlen()-1 above on 1 byte strings, etc.)
    call reverse_bytes
.exit:
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
.loop:
    mov  dl, [eax]
    mov  dh, [ebx]
    inc  eax
    inc  ebx
    cmp  dl, 0
    je   .adone
    cmp  dl, 0
    je   .bdone
    cmp  ecx, 0             ; check if case insensitive compare
    jz   .compare
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
.compare:
    cmp  dl, dh             ; <--- compare
    jb   .aless
    ja   .bless
    jmp  .loop

.adone:
    cmp  dh, 0
    je   .same
.aless:
    mov  eax, -1
    ret
.bdone:
    cmp  dl, 0
    je   .same
.bless:
    mov  eax, 1
    ret
.same:
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
.loop:
    mov  edx, 0             ; upper portion of number to divide - set to 0 to just use eax
    idiv ebx                ; divides eax by ebx
    ; edx=remainder eax=quotient
    add  edx, '0'           ; convert to ASCII char
    mov  [ecx], dl          ; (char*)*scratchp = (byte)edx
    inc  ecx
    cmp  eax, 0
    jne  .loop              ; next char if more (if eax > ebx (radix))
.exit:
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
.loop:
    cmp  eax, ebx           ; src <= dest?
    jae  .exit              ; jae = unsigned, jge = signed
    mov  cl, [eax]          ; cl = *src
    mov  ch, [ebx]          ; ch = *dest
    mov  [eax], ch          ; *src = ch
    mov  [ebx], cl          ; *dest = cl
    inc  eax                ; src++
    dec  ebx                ; dest--
    jmp  .loop
.exit:
    ret

; waits for a char from stdin and stores in current location of [input_p].
; increments <input_p> one byte when complete
; return 0 on EOF or ASCII value of char read otherwise
; return <0 on error
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
    ja   .ok
    je   .eof
.err:
    mov  eax, -1
    ret
.eof:
    mov  eax, 0
    ret
.ok:
    mov  eax, [input_p]
    mov  al,  [eax]
    add  [input_p], DWORD 1 ; increment by a byte (1), not an int (4)
    ret

; read a line of input (until either ENTER inputed or EOF/error)
; data are left in <input> buffer, location in buffer is dependent on
; value of <input_p> when this fx is called
; no return value
_gets:
.loop:
    mov eax, 0
    call _getc
    cmp  al, ENTER
    je   .enter
    cmp  eax, 0             ; EOF
    je   .eof
    jl   .err               ; other error
    jmp  .loop
.eof:
    mov [eof], BYTE 1
    jmp .ok
.err:
    call error
    ret
.enter:
    mov  eax, [input_p]
    dec  eax                ; backup to NEWLINE
    mov  [eax], BYTE 0      ; make sure null terminated instead of NEWLINE
.ok:
    ret

; init globals
init:
    mov  [dsentinel], DWORD 0badd00dh   ; assign sentinel value to help to see if clobbered
    mov  [dsp], DWORD dsentinel         ; compute top of stack/S0
    mov  [dict], DWORD H                ; start of our dictionary - the last primitive Forth word defined
    mov  [input_p], DWORD input
    mov  [eof], BYTE 0                  ; seen EOF on input?
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

__cdecl
next_ptr:
    C_prologue(8)
    mov  eax, C_param(1)    ; 1st param (dict ptr)
    cmp  eax, 0
    jz   .exit              ; return NULL if ptr is NULL
    mov  C_local(1), eax    ; dict entry in local #1
    call dict_after_name
    mov  eax, [eax]         ; value of next ptr into eax for return (dict_after_name+0 == next ptr)
.exit:
    C_epilogue
    ret

; the part of a dictionary entry after the name of the word
; dict entry in eax, results left in eax
dict_after_name:
    push ebx
    push eax
    call _strlen
    mov  ebx, eax
    pop  eax                ; orig ptr
    add  eax, ebx
    inc  eax                ; for the NULL at end of string
    pop  ebx
    ret

; return ptr to dict entry if string <eax> found in dictionary, NULL otherwise
__cdecl_hybrid
find:
    C_prologue(8)
    mov  C_local(1), eax    ; string ptr (word name) to find
    mov  ebx, [dict]
    mov  C_local(2), ebx    ; currnt dict entry
.loop:
    mov  eax, C_local(1)    ; word string ptr
    call _strcmpi           ; ebx = current word name
    cmp  eax, 0
    jz   .exit

    push DWORD C_local(2)   ; dict walker ptr
    call next_ptr
    add  esp, 4             ; 1 param

    mov  ebx, eax           ; next dict entry ptr in ebx (b/c .loop expects it)
    mov  C_local(2), eax    ; next dict entry ptr
    cmp  eax, 0
    jz   .exit
    jmp  .loop
.exit:
    mov  eax, C_local(2)
    C_epilogue
    ret

; execute a word
; eax holds pointer to string of word (name) to execute
execute:
    push eax                ; ptr to word name/str
    call find
    cmp  eax, 0
    jz   .notfound
    call dict_after_name    ; eax is now ptr to the "next" link in header
    add  eax, 4             ; eax is now code ptr
    cmp  [eax+4], DWORD 0   ; is "param ptr" set?
    jnz  .forth
.primitive:                 ; word is an asm primitive
    mov  eax, [eax]         ; dereference code pointer to addr
    call eax
    jmp  .exit
.forth:                     ; word is a list of forth words
    ; TODO
.exit:
    pop  eax
    mov  eax, 0
    ret
.notfound:
    mov  eax, word_not_found_str
    call _putstr
    pop  eax                ; ptr to word name/str
    call _puts
    mov  eax, -1
    ret

; Forth's quit - outer loop that calls INTERPRET
quit:
    mov  [input_p], DWORD input
    call _gets              ; leaves string in [input]
    cmp  [eof], BYTE 0
    jne  .exit
    mov  eax, input
    call interpret
    call ok
    @CR
    jmp  quit
.exit:
    ret

; handle input/words found in <eax> pointer
interpret:
    mov  [tokenp], eax      ; token walker (TODO move pointer to be local to this function)
.loop:
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
    jae  .exit              ; at/past last token
    jmp  .loop
.exit:
    mov  eax, 0
    ret


