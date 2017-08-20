#include "stdio.h"

int add(int x, int y) lang C
{
    //#include "stdio.h"
    return x + y;
}

int sub(int x, int y) lang nasm
{
    mov eax, edi
    sub eax, esi
    ret
}

int main(int argc, char** argv) lang C
{
    printf("%d\n", sub(add(3,5), 4));
    return 0;
}
