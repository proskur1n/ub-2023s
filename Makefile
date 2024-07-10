NAME := gesamt
HEADERS := util.h symtable.h codegen.h
CFLAGS := -Wall -Wextra

all: CFLAGS += -DNDEBUG
all: $(NAME)

debug: $(NAME)

$(NAME): lex.yy.c parser.tab.c util.c codegen.c
	gcc -o $@ $(CFLAGS) -g $^

lex.yy.c: oxout.l
	flex $<

parser.tab.h:
parser.tab.c: oxout.y
	bison -o parser.tab.c -Werror -d $<

oxout.y:
oxout.l: parser.y scanner.l $(HEADERS)
	ox parser.y scanner.l

codegen.c: codegen.bfe $(HEADERS)
	bfe $< | iburg > $@

clean:
	rm -f oxout.* parser.tab.* lex.yy.c codegen.c *.s $(NAME)

.PHONY: all debug clean
