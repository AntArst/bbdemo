/*
 * Hello BBDemo - Example custom application
 * This demonstrates how to add custom commands to a Yocto-built system
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char *argv[])
{
    printf("Hello from BBDemo!\n");
    printf("This is a custom application built with Yocto/BitBake.\n");
    
    if (argc > 1) {
        printf("Arguments received: ");
        for (int i = 1; i < argc; i++) {
            printf("%s ", argv[i]);
        }
        printf("\n");
    }
    
    printf("System information:\n");
    printf("  PID: %d\n", getpid());
    printf("  UID: %d\n", getuid());
    
    return 0;
}

