
%include "defines.inc"

extern _push_asm
extern _pop_asm
extern _emit_asm

extern _putstr
extern _puts

extern _strcmpi
extern _strlen
extern _strtok

extern H


global eol
eol:
    push eax
    mov  eax, eol_str
    call _putstr
    pop  eax
    ret


;; ----------


section .data
    banner_str: cstr('uforth v0.9.2')
    ok_str:     cstr(' ok')
%ifidn __OUTPUT_FORMAT__, macho32
    eol_str:    db CR, NL, 0
%else
    eol_str:    db NL, 0
%endif

%define STACK_SIZE      128
%define INPUT_BUFSIZE   128
%define SCRATCH_BUFSIZE 128

global dict
global dsp
global dsentinel
global scratch

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
; support functions
;
; -----------------------------

; ( -- n | -- , attempts to parse a decimal number from <eax> and push it on the Forth stack )
; <n> will by 10x too large if we encounter an ASCII char outside '0'..'9' but otherwise ok
; if empty string given, will push 0 to Forth stack
; does not handle negative numbers or other bases, currently
number:
    mov  edx, eax
    mov  eax, 0
.loop:
    mov  ebx, 0
    mov  bl, [edx]          ; bl = (char)*p
    cmp  ebx, 0
    jz   .done              ; stop on \0; will push 0 if zero-length input given
    cmp  ebx, '0'
    jb   .badchar
    cmp  ebx, '9'
    ja   .badchar
    sub  ebx, '0'           ; difference is decimal 0..9
    imul eax, 10            ; 10 = base; ok to do when eax = 0 b/c 0*10 still = 0
    add  eax, ebx
    inc  edx
    jmp  .loop
.done:
    @PUSH_EAX               ; uses eax - push result on data stack
    mov  eax, 0
    ret
.badchar:
    mov  eax, -1
    ret


; writes eax as unsigned decimal string to <scratch> and return length in eax
global _itoa
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
    mov  [ecx], byte 0      ; always terminate string
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
global reverse_bytes
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
global forth_stack_depth
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
    jz   .trynumber
    call dict_after_name    ; eax is now ptr to the "next" link in header
    add  eax, 4             ; eax is now code ptr
    cmp  [eax+4], DWORD 0   ; is "param ptr" set?
    jnz  .forth
.primitive:                 ; word is an asm primitive
    mov  eax, [eax]         ; dereference code pointer to addr
    call eax
    jmp  .ok
.forth:                     ; word is a list of forth words
    ; TODO
.ok:
    pop  eax
    mov  eax, 0
    ret
.trynumber:
    mov  eax, [esp]         ; pull eax from stack w/o popping
    call number
    cmp  eax, 0
    jnz  .notfound
    jmp  .ok
.notfound:
    pop  eax
    mov  eax, -1
    ret

; Forth's quit - outer loop that calls INTERPRET
quit:
.loop:
    mov  [input_p], DWORD input
    call _gets              ; leaves string in [input]
    cmp  [eof], BYTE 0
    jne  .exit
    mov  eax, input
    call interpret
    call ok
    @CR
    ; TODO move EOF check here?
    jmp  .loop
.exit:
    ret

; handle input/words found in <eax> pointer
interpret:
    mov  [tokenp], eax      ; token walker (TODO move pointer to be local to this function)
.loop:
    call _strtok
    push eax                ; token size
    cmp  eax, 0
    jz   .skip              ; skip zero-length tokens
    mov  eax, [tokenp]
    call execute
.skip:
    pop  ecx                ; token size
    cmp  eax, 0             ; will remain zero for zero-length tokens = ok
    jnz  .error
.next:
    mov  eax, [tokenp]
    add  eax, ecx
    inc  eax
    mov  [tokenp], eax
    mov  ebx, [input_p]
    cmp  eax, ebx
    jae  .exit              ; at/past last token
    jmp  .loop
.error:                     ; output "<word>? " on unknown word
    mov  eax, [tokenp]
    call _putstr
    putc('?')
    mov  eax, -1
    ret
.exit:
    mov  eax, 0
    ret

;;
