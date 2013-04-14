
EXECUTABLE=uforth
SOURCES=uforth.asm
OBJECTS=uforth.o

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
	@ld -s -o $(EXECUTABLE) $(OBJECTS)

.asm.o:
	@nasm -f elf $<

clean:
	@rm -f $(EXECUTABLE) $(OBJECTS)

