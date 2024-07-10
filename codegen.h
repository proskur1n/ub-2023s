#pragma once

#include "symtable.h"

enum op {
    OP_IMMEDIATE = 1,
    OP_REGISTER,
    OP_MEMORY,
    OP_NOT,
    OP_NEGATE,
    OP_ADD,
    OP_MULTIPLY,
    OP_OR,
    OP_GREATER,
    OP_NOT_EQUAL,
    OP_NEW,
    OP_PARAM,
    OP_CALL,
};

enum guarded {
    GUARDED_BREAK,
    GUARDED_CONTINUE,
};

struct tree;

void codegen_begin_class(struct symtable const *isym, char const *name, struct symtable const *members, struct symtable const *methods);
void codegen_end_class(void);
void codegen_begin_method(char const *name, struct symtable const *params);
void codegen_end_method(void);
void codegen_begin_cond(void);
void codegen_end_cond(void);
void codegen_begin_guarded(struct tree *);
void codegen_end_guarded(enum guarded);

void codegen_generate_return_statement(struct tree *);
void codegen_generate_definition_statement(char const *name, struct tree *);
void codegen_generate_assignment_statement(char const *name, struct tree *);
void codegen_generate_expression_statement(struct tree *);

struct tree *tree_new_immediate(long value);
struct tree *tree_new_variable(char const *name);
struct tree *tree_new_operator(enum op, struct tree *left, struct tree *right);
struct tree *tree_new_operator_new(struct sym const *clazz);
struct tree *tree_new_function_call(const char *func_name, struct tree *param_tree);
