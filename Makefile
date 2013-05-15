
OUTPUT=bin

EXECUTABLE=$(OUTPUT)/uforth
OBJECTS=$(OUTPUT)/uforth.o $(OUTPUT)/cstring.o $(OUTPUT)/dict.o

SOURCES=uforth.asm cstring.asm dict.asm

AS=nasm
ASFLAGS=-g

RM=rm -f

LD=ld
LDFLAGS=

CP=cp


UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S), Darwin)
	ASFLAGS += -f macho32
	LDFLAGS += -arch i386
else
	ASFLAGS += -f elf32
	LDFLAGS += -m elf_i386
endif


# delete default suffix list
.SUFFIXES:

.PHONY: default
default: $(SOURCES) $(EXECUTABLE)

.PHONY: all
all: default

.PHONY: run
run: $(EXECUTABLE)
	@./$(EXECUTABLE)

$(OUTPUT):
	@mkdir -p $(OUTPUT)

$(EXECUTABLE): $(OUTPUT) $(OBJECTS)
	@$(LD) $(LDFLAGS) -o $(EXECUTABLE) $(OBJECTS)

$(OUTPUT)/%.o: %.asm
	@$(AS) $(ASFLAGS) -o $@ $^

.PHONY: clean
clean:
	@$(RM) $(EXECUTABLE) $(OBJECTS)

.PHONY: strip
strip:
	@strip $(EXECUTABLE) $(OBJECTS)
