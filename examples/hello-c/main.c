#include <stdio.h>
#include <sys/utsname.h>

int main(void) {
    struct utsname info;
    printf("============================================\n");
    printf("  Hello from MaiaLinux on Anbernic RG353V!\n");
    printf("============================================\n");
    if (uname(&info) == 0) {
        printf("System : %s %s\n", info.sysname, info.release);
        printf("Arch   : %s\n", info.machine);
    }
    printf("Ready for C/C++ development on the console.\n");
    return 0;
}
