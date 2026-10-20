#include <stdio.h>
int main(void) { volatile int a = 10, b = 0; printf("%d\n", a / b); return 0; }
