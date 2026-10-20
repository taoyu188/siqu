#include <stdio.h>
int check(int x) {
    if (x > 0) return 1;
}
int main(void) {
    printf("%d\n", check(3));
    return 0;
}
