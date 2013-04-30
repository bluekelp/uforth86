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

; index-1 based local parameter (e.g., C_local(1) is our first local dword
%define C_local(x) [ebp-(x*4)]

; index-1 based parameter to routine (e.g., C_param(1) = first param) - always assumes dword param size
; C_param(0) is undefined
%define C_param(x)  [ebp+(4+(x*4))]


;; -----


%macro @PUSH_EAX 0
    call _push_asm
%endmacro

%macro @POP_EAX 0
    call _pop_asm
%endmacro

%macro @EMIT 0
    call _emit_asm
%endmacro

%macro @CR 0
    call eol
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


