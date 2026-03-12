#define _GNU_SOURCE
#include <stdio.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <errno.h>
#include <string.h>

int main() {
    printf("Testing blocked syscalls...\n");
    
    // Test clone3 (syscall 435 on x86_64)
    printf("\n1. Attempting clone3()...\n");
    long ret = syscall(435, NULL, 0);
    printf("   Result: %ld, errno: %d (%s)\n", ret, errno, strerror(errno));
    
    // Test bpf (syscall 321)
    printf("\n2. Attempting bpf()...\n");
    ret = syscall(321, 0, NULL, 0);
    printf("   Result: %ld, errno: %d (%s)\n", ret, errno, strerror(errno));
    
    // Test perf_event_open (syscall 298)
    printf("\n3. Attempting perf_event_open()...\n");
    ret = syscall(298, NULL, 0, -1, -1, 0);
    printf("   Result: %ld, errno: %d (%s)\n", ret, errno, strerror(errno));
    
    // Test userfaultfd (syscall 323)
    printf("\n4. Attempting userfaultfd()...\n");
    ret = syscall(323, 0);
    printf("   Result: %ld, errno: %d (%s)\n", ret, errno, strerror(errno));
    
    printf("\nTest complete. Check for EPERM (errno 1) indicating blocked syscalls.\n");
    sleep(300);
    return 0;
}
