
EXECUTABLE=uforth
SOURCES=uforth.asm
OBJECTS=uforth.o

AS=nasm
ASFLAGS=-g

RM=rm -f

LD=ld
LDFLAGS=


UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S), Darwin)
	ASFLAGS += -f macho32
	LDFLAGS += -arch i386
else
	ASFLAGS += -f i386
	ARCH=elf32
endif


# delete default suffix list
.SUFFIXES:

# NB - .asm isn't a default suffix known to make(1) (but .a and probably .as and .S are)
.SUFFIXES: .asm .o

.PHONY: default
default: $(SOURCES) $(EXECUTABLE)

.PHONY: run
run: $(EXECUTABLE)
	@./$(EXECUTABLE)

$(EXECUTABLE): $(OBJECTS)
	@$(LD) $(LDFLAGS) -o $(EXECUTABLE) $(OBJECTS)

.asm.o:
	@$(AS) $(ASFLAGS) $<

clean:
	@$(RM) $(EXECUTABLE) $(OBJECTS)

