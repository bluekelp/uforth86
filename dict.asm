
%include "defines.inc"


extern dsp
extern dsentinel
extern rsp_
extern rsentinel

extern _itoa
extern forth_stack_depth
extern scratch
extern _putstr
extern dict

global H
global _emit_asm
global _push_asm
global _pop_asm

; -----------------------------
;
; Forth primitive words, with dictionary headers
;
; -----------------------------

; DICT_PRIMITIVE name_cstr, nextDictEntry, code_ptr
%macro DICT_PRIMITIVE 3
    cstr(%1)                ; name (null terminated)
    dd  %2                  ; next dict ptr
    dd  %3                  ; code ptr
    dd  0                   ; param ptr
%endmacro

; DICT_WORD name_cstr, nextDictEntry, param_ptr
%macro DICT_WORD 3
    cstr(%1)                ; name (null terminated)
    dd  %2                  ; next dict ptr
    dd  0                   ; code ptr
    dd  %3                  ; param ptr
%endmacro

; ( -- n, pushes <eax> into the stack as a cell )
PUSH_EAX:
DICT_PRIMITIVE 'push_eax', NULL, _push_asm
_push_asm:
    push ebx
    mov  ebx, [dsp]         ; load pointer
    sub  ebx, 4             ; decrement (push)
    ; TODO check overflow?
    mov  [ebx], eax         ; store value
    mov  [dsp], ebx         ; update pointer
    pop  ebx
    ret

; ( n -- , pop a cell off stack, leaves it in <eax> )
POP_EAX:
DICT_PRIMITIVE 'pop_eax', PUSH_EAX, _pop_asm
_pop_asm:
    push ebx
    mov  ebx, [dsp]         ; load pointer
    cmp  ebx, dsentinel
    jae  .underflow
    mov  eax, [ebx] ; <---- ; fetch value
    add  ebx, 4             ; increment (pop)
    mov  [dsp], ebx         ; update pointer
    jmp  .exit
.underflow:
    mov  eax, 0
.exit:
    pop  ebx
    ret

; ( c -- , pops a cell and prints its first byte to stdout )
EMIT:
DICT_PRIMITIVE 'emit', POP_EAX, _emit_asm
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


; ( -- n , push address of top of stack (i.e., the empty stack position) to stack )
S0:
DICT_PRIMITIVE 's0', EMIT, _s0_asm
_s0_asm:
    mov  eax, dsentinel
    @PUSH_EAX
    ret

; ( -- n , push address of current stack pointer to stack )
TICK_S:
DICT_PRIMITIVE "'s", S0, _tick_s_asm
_tick_s_asm:
    mov  eax, [dsp]
    @PUSH_EAX
    ret

; ( -- x , compute current stack depth and push that value onto stack )
DEPTH:
DICT_PRIMITIVE 'depth', TICK_S, _depth_asm
_depth_asm:
    call forth_stack_depth
    @PUSH_EAX
    ret

; ( x -- , pop one number off stack and print it )
DOT:
DICT_PRIMITIVE '.', DEPTH, _dot_asm
_dot_asm:
    @POP_EAX
    call _itoa
    mov  eax, scratch
    call _putstr
    putc(' ')
    ret

; ( x y -- z , add x and y and push result )
PLUS:
DICT_PRIMITIVE '+', DOT, _plus_asm
_plus_asm:
    @POP_EAX
    push eax                ; POP_EAX clobbers ebx
    @POP_EAX
    pop  ebx
    add  eax, ebx
    @PUSH_EAX
    ret

; ( x y -- z , subtract y from x and push result )
MINUS:
DICT_PRIMITIVE '-', PLUS, _minus_asm
_minus_asm:
    @POP_EAX
    push eax                ; POP_EAX clobbers ebx
    @POP_EAX
    pop  ebx
    sub  eax, ebx
    @PUSH_EAX
    ret

; ( x y -- z , multiply x times y and push result )
MULTIPLY:
DICT_PRIMITIVE '*', MINUS, _multiply_asm
_multiply_asm:
    @POP_EAX
    push eax                ; POP_EAX clobbers ebx
    @POP_EAX
    pop  ebx
    imul eax, ebx
    @PUSH_EAX
    ret

; ( n -- , remove element from top of stack )
DROP:
DICT_PRIMITIVE 'drop', MULTIPLY, _drop_asm
_drop_asm:
    push eax
    @POP_EAX
    pop  eax
    ret

DUP:
DICT_PRIMITIVE 'dup', DROP, _dup_asm
_dup_asm:
    @POP_EAX
    @PUSH_EAX
    @PUSH_EAX
    ret

; ( a -- v , loads addr of memory at <a> and puts value as <v> )
LOAD_ADDR:
DICT_PRIMITIVE '@', DUP, _load_addr_asm
_load_addr_asm:
    @POP_EAX
    mov  eax, [eax]
    @PUSH_EAX
    ret

; ( v a -- , puts value v at address a )
STORE_ADDR:
DICT_PRIMITIVE '!', LOAD_ADDR, _store_addr_asm
_store_addr_asm:
    push ebx
    @POP_EAX                    ; addr
    mov  ebx, eax
    @POP_EAX                    ; value
    mov  [ebx], eax
    pop  ebx
    ret

; ( a -- v , loads a byte from memory at addr <a> and puts value as <v> on stack ; v will be in [0, 255] inclusive )
LOAD_8_ADDR:
DICT_PRIMITIVE 'c@', STORE_ADDR, _load_8_addr_asm
_load_8_addr_asm:
    @POP_EAX
    push ebx
    mov  ebx, 0
    mov  bl, [eax]
    mov  eax, ebx
    pop  ebx
    @PUSH_EAX
    ret

; ( v a -- , puts 8-bit value v at address a ; if cell value <v> is >255 only 8 least significant bits stored )
STORE_8_ADDR:
DICT_PRIMITIVE 'c!', LOAD_8_ADDR, _store_8_addr_asm
_store_8_addr_asm:
    push ebx
    @POP_EAX                    ; addr
    mov  ebx, eax
    @POP_EAX                    ; value
    mov  [ebx], al
    pop  ebx
    ret

; ( a b -- b a , swap top two cells )
SWAP:
DICT_PRIMITIVE 'swap', STORE_8_ADDR, _swap_asm
_swap_asm:
    @POP_EAX
    push eax
    @POP_EAX
    mov  ebx, eax
    pop  eax
    @PUSH_EAX
    mov  eax, ebx
    @PUSH_EAX
    ret

; ( a b c -- b c a , rotate cells )
; highly inefficient - redo to access cells directly? (need to properly detect underflow)
ROT:
DICT_PRIMITIVE 'rot', SWAP, _rot_asm
_rot_asm:
    C_prologue 12
    @POP_EAX
    mov  C_local(3), eax
    @POP_EAX
    mov  C_local(2), eax
    @POP_EAX
    mov  C_local(1), eax

    mov  eax, C_local(2)
    @PUSH_EAX
    mov  eax, C_local(3)
    @PUSH_EAX
    mov  eax, C_local(1)
    @PUSH_EAX
    C_epilogue
    ret

; ( a b -- a b a )
OVER:
DICT_PRIMITIVE 'over', ROT, _over_asm
_over_asm:
    @POP_EAX                ; b
    mov  ebx, eax
    @POP_EAX                ; a
    mov  ecx, eax
    mov  eax, ebx
    @PUSH_EAX               ; a
    mov  eax, ecx
    @PUSH_EAX               ; b
    mov  eax, ebx
    @PUSH_EAX
    ret

; ( -- 0 , pushes 0 on the stack )
PUSH_0:
DICT_PRIMITIVE '0', OVER, _push_0_asm
_push_0_asm:
    mov  eax, 0
    @PUSH_EAX
    ret

; ( -- 1 , pushes 1 on the stack )
PUSH_1:
DICT_PRIMITIVE '1', PUSH_0, _push_1_asm
_push_1_asm:
    mov  eax, 1
    @PUSH_EAX
    ret

; ( -- 4 , computes the number 4 (useful for adding/subtracting cells addresses or DWORD pointer increment/decrements )
COMPUTE_FOUR:
DICT_WORD 'compute4', PUSH_1, _compute_4_list
_compute_4_list:
    dd  PUSH_1
    dd  DUP
    dd  PLUS
    dd  DUP
    dd  MULTIPLY
    dd  0

; ( x1 x2 ... xN -- , clears stack ; implemented as a Forth word to test ability to call and chain other words together )
CLEAR:
DICT_WORD 'clear', COMPUTE_FOUR, _clear_list
_clear_list:
    dd  S0
    dd  S0
    dd  COMPUTE_FOUR
    dd  PLUS            ; add 4 to S0 (S0+4 = dsp)
    dd  STORE_ADDR
    dd  0

; ( -- , do nothing ; implemented as a Forth word to test Forth's ability to stop when a null in the param list is encountered )
__LAST:
NOOP:
DICT_WORD 'noop', CLEAR, _noop_list
_noop_list:
    dd 0

;; words to add:
; ?DUP
; : ( COMPILER )
; FORGET xxx
; DO ... LOOP
; -2 (see p50)
; IF ... ELSE .. THEN
; ." ( PRINT STRING )
; ' xxx ( FIND xxx )
; =
; <
; >
; 0=
; 0<
; 0>
; NOT
; AND
; OR
; XOR    (not a standard Forth word?)
; ABORT"
; ?STACK
; 1+
; 1-
; 2+
; 2-
; 2+
; 2/
; ABS
; MIN
; MAX
; >R (see p110)
; R>
; I
; I'
; J
;
; ---- loops (Ch 6 p133)
; +LOOP
; BEGIN ... UNTIL
; BEGIN ... WHILE ... REPEAT
; LEAVE
; PAGE (not really a loop construct)
; U.R ( unsigned right justified number print )
; QUIT (redo in Forth)
;
; ----
; U.
; U/MOD
; U<
; DO ... /LOOP
;
; ---- OR consider S. S/MOD S< and such to make signed math the odd case
;
; ----
; HEX
; OCTAL
; DECIMAL
; BASE
;
; ---- double size numbers (p165-166)
; D.
; DABS
; D+
; D-
; DNEGATE
; DMAX
; DMIN
; D=
; D0=
; D<
; DU<
; D.R
;
; #
; <#
; #>
; #S
; TYPE
; HOLD
; SIGN
;
; ---- mixed length opers
; M+
; M/
; M*
; M*/
;
; ---- above described p177-179
;
; ---- "higher" math
; *
; /
; /MOD
; MOD
; */
; */MOD
;
; ---- 2x words
; 2SWAP
; 2DUP
; 2OVER
; 2DROP
;
; ---- blocks and editing (See Ch 3)
; LIST
; LOAD
; L (current/last block?)
; T ( n -- , select current line)
; P ( puts rest of line (stdin) into current block line ; uses gets but stores to block ; see p65 for more like "P  " )
; F
; I
; E
; D
; R
; TILL
; U
; X
; WIPE
; N
; B
; FLUSH
; COPY
; S
; M
; ^
; EMPTY
;
; ---- p183 Ch 8
; VARIABLE xxx
; EXECUTE (need to replace asm verstion)
; +!                            : +! DUP @ ROT + SWAP ! ;
; ?
; CONSTANT xxx
; 2!
; 2@
; 2CONSTANT xxx
; ALLOT
; FILL
; ERASE
; DUMP
; C!
; C@
; CREATE xxx
; C,
; ,
; BASE
; 2VARIABLE xxx
; 0
; 1
; 0.
;
; ----
; INTERPRET                     : INTERPRET  BEGIN -' IF NUMBER ELSE EXECUTE ?STACK ABORT" STACK EMPTY" THEN 0 UNTIL ;
; -'
; HERE                          : HERE H @ ;
; ,                             : , HERE ! 2 ALLOT ;
; ' xxx
; [']
; EXIT
; QUIT
; PAD                           : PAD HERE <XXX> + ;  (where <XXX> is some internal buffer size/padding)
; OPERATOR
;
; ----
; SCR
; R#
; BASE
; H
; CONTEXT
; CURRENT
; >IN
; BLK
; OFFSET
; USER
;
; ---- contexts
; FORTH
; EDITOR
; ASSEMBLER
;
; ----
; DEFINITIONS                   : DEFINITIONS   CONTEXT @   CURRENT ! ;
; LOCATE xxx
;
; ----
; LIST
; UPDATE
; FLUSH
; SAVE-BUFFERS
; EMPTY-BUFFERS
; COPY
; BLOCK
; BUFFER
; -TRAILING
; >TYPE
; TYPE
; MOVE
; CMOVE
; <CMOVE
; KEY                           ( !! )
; EXPECT
; WORD
; TEXT
; QUERY
; >IN
; TEXT                          : TEXT   PAD  72 32 FILL  WORD  COUNT PAD SWAP <CMOVE ;
; >BINARY
; CONVERT
; NUMBER                        (p279)
; PTR
; COUNT
; -TEXT
; CMOVE
; BLANK
;
; ----
; CREATE
; DOES>
; IMMEDIATE
; BEGIN                         : BEGIN HERE ; IMMEDIATE
; COMPILE xxx
; [COMPILE] xxx
; LITERAL
; (LITERAL)   (not sure about this one)
; [                             -- leave compile mode
; ]                             -- enter compile mode
; ]                             : ]  BEGIN -' IF (NUMBER) LITERAL ELSE (check precedence bit) IF EXECUTE ?STACK ABORT" STACK EMPTY" ELSE 2- , THEN THEN 0 UNTIL ;
;
; -- implemented in terms of others (put in a block? expect compiled from stdin?)
; SPACE                         : SPACE 20 EMIT ;
;
; ---- the assembler
; ---- date/time functions
; ---- more OS sys_calls (open, unlink, stat, brk, fork(!), close, etc.)
; ---- memcpy
; ---- see 4-1 for summary of Forth words (by category)


; -- add new Forth words *above* this one - keep this as head of list so init code doesn't have to be updated
H:
DICT_PRIMITIVE 'h', __LAST, _h_asm
_h_asm:
    mov eax, [dict]
    @PUSH_EAX
    ret

