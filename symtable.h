#pragma once

#define FOREACH_SYMBOL(elem, list) for (\
    struct sym *_list_iter = (struct sym *)(list), *elem;\
    _list_iter != NULL && ((elem = ((struct symtable *)_list_iter)->sym) || 1);\
    _list_iter = (struct sym *)((struct symtable *)_list_iter)->next)

enum type {
    TYPE_INT,
    TYPE_OBJECT,
};

enum symtype {
    SYMTYPE_FUNCTION, // Used for both selectors and method implementations.
    SYMTYPE_CLASS,
    SYMTYPE_VARIABLE,
};

struct sym {
    char *name;
    enum symtype symtype;

    union {
        struct {
            enum type rettype;
            struct symtable *params;
        } func;

        struct {
            struct symtable *members;
            struct symtable *methods;
        } clazz;

        struct {
            enum type type;
        } var;
    };
};

struct symtable {
    struct sym *sym;
    struct symtable *next;
};
