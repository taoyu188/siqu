#include <stdio.h>
int main(void) {
    int n = 5;
    int *p = &n;
    char *q;
    q = p;
    printf("%p\n", (void *)q);
    return 0;
}
