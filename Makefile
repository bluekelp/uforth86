
EXECUTABLE=uforth
SOURCES=uforth.asm
OBJECTS=uforth.o

AS=nasm
ASFLAGS=-g -f macho32

RM=rm -f

LD=ld
LDFLAGS=-arch i386
#LDFLAGS=-s

# delete default suffix list
.SUFFIXES:

# NB - .asm isn't a default suffix known to make(1) (but .a and probably .as and .S are)
.SUFFIXES: .asm .o

.PHONY: default
default: $(SOURCES) $(EXECUTABLE)

.PHONY: all
all: default

.PHONY: run
run: $(EXECUTABLE)
	@./$(EXECUTABLE)

$(EXECUTABLE): $(OBJECTS)
	@$(LD) $(LDFLAGS) -o $(EXECUTABLE) $(OBJECTS)

.asm.o:
	@$(AS) $(ASFLAGS) $<

clean:
	@$(RM) $(EXECUTABLE) $(OBJECTS)

