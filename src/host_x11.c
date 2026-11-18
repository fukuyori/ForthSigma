/* Keep libc's struct stat (including musl's timespec bitfields) behind C ABI. */
#include <sys/stat.h>

int sigma_x11_authority_file(int fd) {
    struct stat status;
    return fstat(fd, &status) == 0 && S_ISREG(status.st_mode) &&
        status.st_size >= 0 && status.st_size <= 1024 * 1024;
}
