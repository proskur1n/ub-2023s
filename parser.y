%{
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdnoreturn.h>
#include <stdbool.h>
#include <stdarg.h>
#include <assert.h>
#include "codegen.h"
#include "util.h"

static noreturn void semantic_error(char const *format, ...);
static void check_assignable(enum type left, enum type right);
static enum type check_callable(struct symtable *table, char *name, struct symtable *params);
static enum type check_unary_operator(int op, enum type operand);
static enum type check_binary_operator(int op, enum type left, enum type right);

static struct sym *lookup(struct symtable *table, char *name, enum symtype symtype);
static struct symtable *put_class(struct symtable *table, char *name, struct symtable *members, struct symtable *methods);
static struct symtable *put_function(struct symtable *table, char *name, enum type rettype, struct symtable *params);
static struct symtable *put_variable(struct symtable *table, char *name, enum type type);
static struct symtable *reverse(struct symtable *table);
static struct symtable *concat(struct symtable *first, struct symtable *second);

extern int yylineno;
int yylex();
void yyerror(char const *msg);
%}

%token TOK_OBJECT TOK_INT TOK_CLASS TOK_END TOK_RETURN TOK_COND TOK_CONTINUE TOK_BREAK TOK_NOT
    TOK_OR TOK_NEW TOK_NULL TOK_LEFT_ARROW TOK_RIGHT_ARROW TOK_ID TOK_NUM

@traversal @postorder typecheck /* Final semantic checks that could not be performed while parsing */
@traversal @preorder codegen /* Generate assembly instructions */

@autoinh isym
@autosyn ssym type name

@attributes { char *name; } TOK_ID
@attributes { long value; } TOK_NUM
@attributes { enum type type; } TOK_OBJECT TOK_INT Type

@attributes {
    struct symtable *hoist;
    struct symtable *isym;
} Program

@attributes {
    char *name;
    enum type rettype;
    struct symtable *params;
} Selector

@attributes {
    struct symtable *rev_params;
} TypeRepeat

@attributes {
    char *name;
    struct symtable *members;
    struct symtable *methods;
    struct symtable *isym;
} Class

@attributes {
    struct symtable *rev_members;
    struct symtable *rev_methods;
    struct symtable *isym;
} MemberList

@attributes {
    char *name;
    enum type type;
} Member Par

@attributes {
    char *name;
    enum type rettype;
    struct symtable *params;
    struct symtable *isym;
} Method

@attributes {
    struct symtable *rev_params;
} Pars

@attributes {
    struct symtable *isym;
    struct symtable *ssym;
    @autoinh enum type rettype;
} Stats Stat

@attributes {
    struct symtable *isym;
    @autoinh enum type rettype;
} Return Cond GuardedList Guarded

@attributes {
    struct symtable *isym;
    @autosyn enum type type;
    @autosyn struct tree *tree;
} Expr Term UnaryNot UnaryMinus PlusRepeatAtLeastOne MultRepeatAtLeastOne OrRepeatAtLeastOne

@attributes {
    struct symtable *isym;
    struct symtable *params;
    struct tree *param_tree;
} ExprListAtLeastOne

@attributes {
    int guarded;
} ContinueOrBreak

%%

Start: Program @{ @i @Program.isym@ = @Program.hoist@; @};

Program:
      Selector ';' Program
    @{
        @i @Program.0.hoist@ = put_function(@Program.1.hoist@, @Selector.name@, @Selector.rettype@, @Selector.params@);
    @}
    | Class ';' Program
    @{
        @i @Program.0.hoist@ = put_class(@Program.1.hoist@, @Class.name@, @Class.members@, @Class.methods@);
    @}
    | /* empty */
    @{
        @i @Program.hoist@ = NULL;
    @};

Selector: Type TOK_ID '(' TypeRepeat ')'
    @{
        @i @Selector.rettype@ = @Type.type@;
        @i @Selector.params@ = reverse(@TypeRepeat.rev_params@);
    @};

TypeRepeat:
      TOK_OBJECT
    @{
        @i @TypeRepeat.rev_params@ = put_variable(NULL, NULL, TYPE_OBJECT);
    @}
    | TypeRepeat ',' Type
    @{
        @i @TypeRepeat.0.rev_params@ = put_variable(@TypeRepeat.1.rev_params@, NULL, @Type.type@);
    @};

Type: TOK_INT | TOK_OBJECT;

Class: TOK_CLASS TOK_ID MemberList TOK_END /* Klassendefinition */
    @{
        @i @Class.members@ = reverse(@MemberList.rev_members@);
        @i @Class.methods@ = reverse(@MemberList.rev_methods@);
        @i @MemberList.isym@ = concat(@Class.members@, @Class.isym@);

        @codegen codegen_begin_class(@Class.isym@, @Class.name@, @Class.members@, @Class.methods@);
        @codegen @revorder (true) codegen_end_class();
    @};

MemberList:
      MemberList Member ';'
    @{
        @i @MemberList.0.rev_members@ = put_variable(@MemberList.1.rev_members@, @Member.name@, @Member.type@);
        @i @MemberList.0.rev_methods@ = @MemberList.1.rev_methods@;
    @}
    | MemberList Method ';'
    @{
        @i @MemberList.0.rev_members@ = @MemberList.1.rev_members@;
        @i @MemberList.0.rev_methods@ = put_function(@MemberList.1.rev_methods@, @Method.name@, @Method.rettype@, @Method.params@);
    @}
    | /* empty */
    @{
        @i @MemberList.rev_members@ = NULL;
        @i @MemberList.rev_methods@ = NULL;
    @};

Member: Type TOK_ID /* Objektvariablendefinition */;

Method: Type TOK_ID '(' Pars ')' Stats Return TOK_END /* Methodenimplementierung */
    @{
        @i @Method.rettype@ = @Type.type@;
        @i @Method.params@ = reverse(@Pars.rev_params@);
        @i @Stats.isym@ = concat(@Method.params@, @Method.isym@);
        @i @Return.isym@ = @Stats.ssym@;
        @typecheck {
            enum type ret = check_callable(@Method.isym@, @Method.name@, @Method.params@);
            if (ret != @Method.rettype@) {
                semantic_error("Method implementation %s has a wrong return type", @Method.name@);
            }
        }

        @codegen codegen_begin_method(@Method.name@, @Method.params@);
        @codegen @revorder (true) codegen_end_method();
    @};

Pars:
      Par
    @{
        @i @Pars.rev_params@ = put_variable(NULL, @Par.name@, @Par.type@);
    @}
    | Pars ',' Par
    @{
        @i @Pars.0.rev_params@ = put_variable(@Pars.1.rev_params@, @Par.name@, @Par.type@);
    @};

Par: Type TOK_ID; /* Parameterdefinition */

Stats:
      Stats Stat ';'
    @{
        @i @Stat.isym@ = @Stats.1.ssym@;
        @i @Stats.0.ssym@ = @Stat.ssym@;
    @}
    | /* empty */
    @{
        @i @Stats.ssym@ = @Stats.isym@;
    @};

Stat:
      Return
    @{
        @i @Stat.ssym@ = @Stat.isym@;
    @}
    | Cond
    @{
        @i @Stat.ssym@ = @Stat.isym@;
    @}
    | Type TOK_ID TOK_LEFT_ARROW Expr /* Variablendefinition */
    @{
        @i @Stat.ssym@ = put_variable(@Stat.isym@, @TOK_ID.name@, @Type.type@);
        @typecheck check_assignable(@Type.type@, @Expr.type@);

        @codegen codegen_generate_definition_statement(@TOK_ID.name@, @Expr.tree@);
    @}
    | TOK_ID TOK_LEFT_ARROW Expr /* Zuweisung */
    @{
        @i @Stat.ssym@ = @Stat.isym@;
        @typecheck check_assignable(lookup(@Stat.isym@, @TOK_ID.name@, SYMTYPE_VARIABLE)->var.type, @Expr.type@);

        @codegen codegen_generate_assignment_statement(@TOK_ID.name@, @Expr.tree@);
    @}
    | Expr /* Ausdrucksanweisung */
    @{
        @i @Stat.ssym@ = @Stat.isym@;

        @codegen codegen_generate_expression_statement(@Expr.tree@);
    @};

Return: TOK_RETURN Expr
    @{
        @typecheck if (@Expr.type@ != @Return.rettype@) semantic_error("Return type mismatch");
        @codegen codegen_generate_return_statement(@Expr.tree@);
    @};

Cond: TOK_COND GuardedList TOK_END
    @{
        @codegen codegen_begin_cond();
        @codegen @revorder (true) codegen_end_cond();
    @}
    ;

GuardedList: GuardedList Guarded ';' | /* empty */;

Guarded:
      Expr TOK_RIGHT_ARROW Stats ContinueOrBreak
    @{
        @typecheck if (@Expr.type@ != TYPE_INT) semantic_error("Guarded condition must be of type int");
        @codegen codegen_begin_guarded(@Expr.tree@);
        @codegen @revorder (true) codegen_end_guarded(@ContinueOrBreak.guarded@);
    @}
    | TOK_RIGHT_ARROW Stats ContinueOrBreak
    @{
        @codegen codegen_begin_guarded(tree_new_immediate(1));
        @codegen @revorder (true) codegen_end_guarded(@ContinueOrBreak.guarded@);
    @}
    ;

ContinueOrBreak:
      TOK_CONTINUE @{ @i @ContinueOrBreak.guarded@ = GUARDED_CONTINUE; @}
    | TOK_BREAK    @{ @i @ContinueOrBreak.guarded@ = GUARDED_BREAK; @}
    ;

Expr: Term
    | UnaryNot
    | UnaryMinus
    | PlusRepeatAtLeastOne
    | MultRepeatAtLeastOne
    | OrRepeatAtLeastOne
    | Term '>' Term
    @{
        @i @Expr.type@ = check_binary_operator('>', @Term.0.type@, @Term.1.type@);
        @i @Expr.tree@ = tree_new_operator(OP_GREATER, @Term.0.tree@, @Term.1.tree@);
    @}
    | Term '#' Term
    @{
        @i @Expr.type@ = check_binary_operator('#', @Term.0.type@, @Term.1.type@);
        @i @Expr.tree@ = tree_new_operator(OP_NOT_EQUAL, @Term.0.tree@, @Term.1.tree@);
    @}
    | TOK_NEW TOK_ID
    @{
        @i @Expr.type@ = TYPE_OBJECT;
        @i @Expr.tree@ = tree_new_operator_new(lookup(@Expr.isym@, @TOK_ID.name@, SYMTYPE_CLASS));
    @};

UnaryNot:
      TOK_NOT Term
    @{
        @i @UnaryNot.type@ = check_unary_operator(TOK_NOT, @Term.type@);
        @i @UnaryNot.tree@ = tree_new_operator(OP_NOT, @Term.tree@, NULL);
    @}
    |
    TOK_NOT UnaryNot
    @{
        @i @UnaryNot.0.tree@ = tree_new_operator(OP_NOT, @UnaryNot.1.tree@, NULL);
    @};

UnaryMinus:
      '-' Term
    @{
        @i @UnaryMinus.type@ = check_unary_operator('-', @Term.type@);
        @i @UnaryMinus.tree@ = tree_new_operator(OP_NEGATE, @Term.tree@, NULL);
    @}
    |
    '-' UnaryMinus
    @{
        @i @UnaryMinus.0.tree@ = tree_new_operator(OP_NEGATE, @UnaryMinus.1.tree@, NULL);
    @};

PlusRepeatAtLeastOne:
      Term '+' Term
    @{
        @i @PlusRepeatAtLeastOne.type@ = check_binary_operator('+', @Term.0.type@, @Term.1.type@);
        @i @PlusRepeatAtLeastOne.tree@ = tree_new_operator(OP_ADD, @Term.0.tree@, @Term.1.tree@);
    @}
    | PlusRepeatAtLeastOne '+' Term
    @{
        @i @PlusRepeatAtLeastOne.0.type@ = check_binary_operator('+', @PlusRepeatAtLeastOne.1.type@, @Term.type@);
        @i @PlusRepeatAtLeastOne.0.tree@ = tree_new_operator(OP_ADD, @PlusRepeatAtLeastOne.1.tree@, @Term.tree@);
    @};

MultRepeatAtLeastOne:
      Term '*' Term
    @{
        @i @MultRepeatAtLeastOne.type@ = check_binary_operator('*', @Term.0.type@, @Term.1.type@);
        @i @MultRepeatAtLeastOne.tree@ = tree_new_operator(OP_MULTIPLY, @Term.0.tree@, @Term.1.tree@);
    @}
    | MultRepeatAtLeastOne '*' Term
    @{
        @i @MultRepeatAtLeastOne.0.type@ = check_binary_operator('*', @MultRepeatAtLeastOne.1.type@, @Term.type@);
        @i @MultRepeatAtLeastOne.0.tree@ = tree_new_operator(OP_MULTIPLY, @MultRepeatAtLeastOne.1.tree@, @Term.tree@);
    @};


OrRepeatAtLeastOne:
      Term TOK_OR Term
    @{
        @i @OrRepeatAtLeastOne.type@ = check_binary_operator(TOK_OR, @Term.0.type@, @Term.1.type@);
        @i @OrRepeatAtLeastOne.tree@ = tree_new_operator(OP_OR, @Term.0.tree@, @Term.1.tree@);
    @}
    | OrRepeatAtLeastOne TOK_OR Term
    @{
        @i @OrRepeatAtLeastOne.0.type@ = check_binary_operator(TOK_OR, @OrRepeatAtLeastOne.1.type@, @Term.type@);
        @i @OrRepeatAtLeastOne.0.tree@ = tree_new_operator(OP_OR, @OrRepeatAtLeastOne.1.tree@ , @Term.tree@);
    @};

Term: '(' Expr ')'
    @{
        @i @Term.tree@ = @Expr.tree@;
    @}
    | TOK_NUM
    @{
        @i @Term.type@ = TYPE_INT;
        @i @Term.tree@ = tree_new_immediate(@TOK_NUM.value@);
    @}
    | TOK_NULL
    @{
        @i @Term.type@ = TYPE_OBJECT;
        @i @Term.tree@ = tree_new_immediate(0);
    @}
    | TOK_ID /* lesender Zugriff */
    @{
        @i @Term.type@ = lookup(@Term.isym@, @TOK_ID.name@, SYMTYPE_VARIABLE)->var.type;
        @i @Term.tree@ = tree_new_variable(@TOK_ID.name@);
    @}
    | TOK_ID '(' ExprListAtLeastOne ')' /* Aufruf */
    @{
        @i @Term.type@ = check_callable(@Term.isym@, @TOK_ID.name@, @ExprListAtLeastOne.params@);
        @i @Term.tree@ = tree_new_function_call(@TOK_ID.name@, @ExprListAtLeastOne.param_tree@);
    @};

ExprListAtLeastOne:
      Expr ',' ExprListAtLeastOne
    @{
        @i @ExprListAtLeastOne.0.params@ = put_variable(@ExprListAtLeastOne.1.params@, NULL, @Expr.type@);
        @i @ExprListAtLeastOne.0.param_tree@ = tree_new_operator(OP_PARAM, @Expr.tree@, @ExprListAtLeastOne.1.param_tree@);
    @}
    | Expr
    @{
        @i @ExprListAtLeastOne.params@ = put_variable(NULL, NULL, @Expr.type@);
        @i @ExprListAtLeastOne.param_tree@ = tree_new_operator(OP_PARAM, @Expr.tree@, NULL);
    @};

%%

static noreturn void semantic_error(char const *format, ...) {
    fprintf(stderr, "Semantic error:\n\t");
    va_list va;
    va_start(va, format);
    vfprintf(stderr, format, va);
    fputs("\n", stderr);
    va_end(va);
    exit(3);
}

static void check_assignable(enum type left, enum type right) {
    if (left != right) {
        semantic_error("Assignment type mismatch");
    }
}

static enum type check_callable(struct symtable *table, char *name, struct symtable *params) {
    assert(name != NULL);
    struct sym *s = lookup(table, name, SYMTYPE_FUNCTION);

    struct symtable *a = s->func.params;
    struct symtable *b = params;
    while (a != NULL && b != NULL) {
        if (a->sym->var.type != b->sym->var.type) {
            break;
        }
        a = a->next;
        b = b->next;
    }
    if (a != NULL || b != NULL) {
        semantic_error("Method %s is not callable with the provided parameters", name);
    }

    return s->func.rettype;
}

static enum type check_unary_operator(int op, enum type operand) {
    (void) op;
    if (operand != TYPE_INT) {
        semantic_error("Unary operator requires an operand of type int");
    }
    return TYPE_INT;
}

static enum type check_binary_operator(int op, enum type left, enum type right) {
    if (op == '#') {
        if (left != right) {
            semantic_error("Binary operator # requires two operands of the same type");
        }
    } else if (left != TYPE_INT || right != TYPE_INT) {
        semantic_error("Binary operator requires two operands of type int");
    }
    return TYPE_INT;
}

static struct sym *lookup(struct symtable *table, char *name, enum symtype symtype) {
    assert(name != NULL);

    while (table != NULL && strcmp(table->sym->name, name) != 0) {
        table = table->next;
    }
    if (table == NULL) {
        semantic_error("Identifier %s is not defined", name);
    }
    if (table->sym->symtype != symtype) {
        switch (symtype) {
        case SYMTYPE_CLASS:
            semantic_error("Identifier %s is not a class", name);
        case SYMTYPE_FUNCTION:
            semantic_error("Method %s doesn't override a selector", name);
        case SYMTYPE_VARIABLE:
            semantic_error("Identifier %s is not assignable", name);
        default:
            assert(0 && "unreachable");
        }
    }
    return table->sym;
}

static struct symtable *put_symbol(struct symtable *table, struct sym *s) {
    if (s->name != NULL) {
        for (struct symtable *t = table; t != NULL; t = t->next) {
            if (strcmp(t->sym->name, s->name) == 0) {
                semantic_error("Identifier '%s' is already defined", s->name);
            }
        }
    }
    struct symtable *newtable = xalloc(sizeof(struct symtable));
    newtable->next = table;
    newtable->sym = s;
    return newtable;
}

static struct symtable *put_class(struct symtable *table, char *name, struct symtable *members, struct symtable *methods) {
    assert(name != NULL);

    for (struct symtable *a = methods; a != NULL; a = a->next) {
        for (struct symtable *b = a->next; b != NULL; b = b->next) {
            if (strcmp(a->sym->name, b->sym->name) == 0) {
                semantic_error("Class '%s' has multiple implementations for the method '%s'", name, a->sym->name);
            }
        }
    }

    struct sym *s = xalloc(sizeof(struct sym));
    *s = (struct sym) {
        .name = name,
        .symtype = SYMTYPE_CLASS,
        .clazz = {
            .members = members,
            .methods = methods,
        },
    };
    return put_symbol(table, s);
}

static struct symtable *put_function(struct symtable *table, char *name, enum type rettype, struct symtable *params) {
    assert(name != NULL);
    struct sym *s = xalloc(sizeof(struct sym));
    *s = (struct sym) {
        .name = name,
        .symtype = SYMTYPE_FUNCTION,
        .func = {
            .rettype = rettype,
            .params = params,
        },
    };
    return put_symbol(table, s);
}

static struct symtable *put_variable(struct symtable *table, char *name, enum type type) {
    // NOTE: `name` may be NULL here (NULL is used for selector parameters).
    struct sym *s = xalloc(sizeof(struct sym));
    *s = (struct sym) {
        .name = name,
        .symtype = SYMTYPE_VARIABLE,
        .var = {
            .type = type,
        },
    };
    return put_symbol(table, s);
}

static struct symtable *reverse(struct symtable *table) {
    struct symtable *result = NULL;
    for (; table != NULL; table = table->next) {
        struct symtable *temp = xalloc(sizeof(struct symtable));
        temp->sym = table->sym;
        temp->next = result;
        result = temp;
    }
    return result;
}

static struct symtable *concat(struct symtable *left, struct symtable *right) {
    if (left == NULL) {
        return right;
    }
    return put_symbol(concat(left->next, right), left->sym);
}

void yyerror(char const *msg) {
    fprintf(stderr, "Parser error on line %d:\n\t%s\n", yylineno, msg);
    exit(2);
}

int main(void) {
    yyparse();
}
