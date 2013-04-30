
%include "defines.inc"

; -----------------------------
;
; c string functions
;
; -----------------------------

extern eol
extern reverse_bytes

; prints the c string pointed to by <eax> to stdout
; returns: void - <eax> undefined
global _putstr
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
global _puts
_puts:
    call _putstr
	call eol
    ret

; string pointer in <eax>, return string length in <eax>
global _strlen
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
global _strtok
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
global _strcpy
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
global _strrev
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
global _strcmp
_strcmp:
    mov  ecx, 0
    call _strcmpx
    ret

; _strcmpi ; uppercase chars are 20h lower than lower case in ASCII
; eax and ebx must not be same
global _strcmpi
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


