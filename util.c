#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "util.h"

void *xalloc(size_t bytes) {
    void *p = calloc(1, bytes);
    if (p == NULL) {
        fputs("no memory\n", stderr);
        exit(9);
    }
    return p;
}

char *xstrdup(char const *s) {
    if (s == NULL) {
        return NULL;
    }
    char *p = strdup(s);
    if (p == NULL) {
        fputs("no memory\n", stderr);
        exit(9);
    }
    return p;
}
