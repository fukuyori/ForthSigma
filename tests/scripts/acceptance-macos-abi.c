/* Verify the installed Apple SDK ABI before using Python ctypes. No timing. */
#include <stddef.h>
#include <stdio.h>
#include <sys/resource.h>
#include <sys/proc_info.h>
#include <libproc.h>
_Static_assert(RUSAGE_INFO_V4 == 4, "RUSAGE_INFO_V4");
_Static_assert(PROC_PIDTASKINFO == 4, "PROC_PIDTASKINFO");
_Static_assert(sizeof(struct rusage_info_v4) == 296, "rusage_info_v4 size");
_Static_assert(offsetof(struct rusage_info_v4, ri_resident_size) == 64, "resident");
_Static_assert(offsetof(struct rusage_info_v4, ri_phys_footprint) == 72, "footprint");
_Static_assert(offsetof(struct rusage_info_v4, ri_lifetime_max_phys_footprint) == 240, "peak");
_Static_assert(offsetof(struct rusage_info_v4, ri_runnable_time) == 288, "tail");
_Static_assert(sizeof(struct proc_taskinfo) == 96, "proc_taskinfo size");
_Static_assert(offsetof(struct proc_taskinfo, pti_virtual_size) == 0, "virtual size");
int main(void) {
    puts("macOS acceptance SDK ABI verified");
    return 0;
}
