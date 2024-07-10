%option noyywrap
%option yylineno
/* Prevent compiler warnings when using the -Wall flag. */
%option noinput
%option nounput

%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "symtable.h"
#include "util.h"
#include "parser.tab.h"

static long parse_dec(char const *str) {
    assert(str[0] != 0);
    long result = 0;
    long m = 1;
    for (char const *s = strchr(str, 0) - 1; s >= str; --s) {
        if ('0' <= *s && *s <= '9') {
            result += (*s - '0') * m;
            m *= 10;
        } else {
            assert(*s == '_');
        }
    }
    return result;
}

static long parse_hex(char const *str) {
    assert(strncmp(str, "0x", strlen("0x")) == 0);
    str += strlen("0x");
    long result = 0;
    long m = 1;
    for (char const *s = strchr(str, 0) - 1; s >= str; --s) {
        if (*s == '_') {
            continue;
        }
        if ('0' <= *s && *s <= '9') {
            result += (*s - '0') * m;
        } else if ('a' <= *s && *s <= 'f') {
            result += (*s - 'a' + 10) * m;
        } else {
            assert('A' <= *s && *s <= 'F');
            result += (*s - 'A' + 10) * m;
        }
        m *= 16;
    }
    return result;
}
%}

whitespace [ \t\n]
identifier [a-zA-Z][_a-zA-Z0-9]*
number10   [0-9][_0-9]*
number16   0x_*[0-9a-fA-F][_0-9a-fA-F]*
number     {number10}|{number16}

%x comment

%%

{whitespace}+ ;
object   return TOK_OBJECT; @{ @TOK_OBJECT.type@ = TYPE_OBJECT; @}
int      return TOK_INT;    @{ @TOK_INT.type@ = TYPE_INT; @}
class    return TOK_CLASS;
end      return TOK_END;
return   return TOK_RETURN;
cond     return TOK_COND;
continue return TOK_CONTINUE;
break    return TOK_BREAK;
not      return TOK_NOT;
or       return TOK_OR;
new      return TOK_NEW;
null     return TOK_NULL;
"<-"     return TOK_LEFT_ARROW;
"->"     return TOK_RIGHT_ARROW;
";"      return ';';
"("      return '(';
","      return ',';
")"      return ')';
"-"      return '-';
"+"      return '+';
"*"      return '*';
">"      return '>';
"#"      return '#';
{identifier} return TOK_ID;  @{ @TOK_ID.name@ = xstrdup(yytext); @}
{number10}   return TOK_NUM; @{ @TOK_NUM.value@ = parse_dec(yytext); @}
{number16}   return TOK_NUM; @{ @TOK_NUM.value@ = parse_hex(yytext); @}
"(*"                BEGIN(comment);
<comment>[^*]*      ;
<comment>"*"+[^*)]* ;
<comment>"*"+")"    BEGIN(INITIAL);
. {
    fprintf(stderr, "Lexical error '%s' on line %d\n", yytext, yylineno);
    exit(1);
}
