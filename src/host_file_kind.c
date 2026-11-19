/* Keep libc's struct stat layout in C; translate-c cannot represent musl's
 * bitfield timespec member on the current Zig toolchain. */
#include <sys/stat.h>
#include <unistd.h>

int sigma_file_is_pipe(int descriptor) {
    struct stat information;
    if (fstat(descriptor, &information) != 0) return -1;
    return S_ISFIFO(information.st_mode) || S_ISSOCK(information.st_mode);
}
