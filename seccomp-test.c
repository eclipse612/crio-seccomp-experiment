#define _GNU_SOURCE
#include <stdio.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <errno.h>
#include <string.h>

struct test { const char *name; long nr; const char *category; };

int main() {
    FILE *f = fopen("/tmp/output.txt", "w");
    struct test tests[] = {
        /* Category 1: Explicit allowlist - CRI-O replaces ALLOW with NOTIFY */
        {"clone3",          435, "allowlist (SCMP_ACT_ALLOW -> NOTIFY)"},
        /* Category 2: Unconditional deny - CRI-O replaces ERRNO with NOTIFY */
        {"swapon",          167, "unconditional deny (SCMP_ACT_ERRNO -> NOTIFY)"},
        {"swapoff",         168, "unconditional deny (SCMP_ACT_ERRNO -> NOTIFY)"},
        {"kexec_load",      246, "unconditional deny (SCMP_ACT_ERRNO -> NOTIFY)"},
        /* Category 3: Conditional deny (caps-based) - also rewritten to NOTIFY */
        {"bpf",             321, "conditional deny (caps-based -> NOTIFY)"},
        {"perf_event_open", 298, "conditional deny (caps-based -> NOTIFY)"},
        {"userfaultfd",     323, "conditional deny (no caps -> NOTIFY)"},
    };
    int n = sizeof(tests) / sizeof(tests[0]);
    const char *prev_cat = "";

    fprintf(f, "Testing blocked syscalls...\n");
    fprintf(stdout, "Testing blocked syscalls...\n");

    for (int i = 0; i < n; i++) {
        if (strcmp(prev_cat, tests[i].category) != 0) {
            fprintf(f, "\n=== %s ===\n", tests[i].category);
            fprintf(stdout, "\n=== %s ===\n", tests[i].category);
            prev_cat = tests[i].category;
        }
        errno = 0;
        long ret = syscall(tests[i].nr, 0, 0, 0, 0, 0);
        fprintf(f, "%d. %s (nr %ld): ret=%ld, errno=%d (%s)\n",
                i+1, tests[i].name, tests[i].nr, ret, errno, strerror(errno));
        fprintf(stdout, "%d. %s (nr %ld): ret=%ld, errno=%d (%s)\n",
                i+1, tests[i].name, tests[i].nr, ret, errno, strerror(errno));
    }

    fprintf(f, "\nDone.\n");
    fprintf(stdout, "\nDone.\n");
    fflush(f); fflush(stdout); fclose(f);
    sleep(300);
    return 0;
}
