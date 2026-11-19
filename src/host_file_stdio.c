/* Worker-owned stdout, retaining CRT text translation without a Forth buffer. */
#include <errno.h>
#include <stdio.h>
#ifdef _WIN32
#include <stdlib.h>
#endif

int sigma_write_stdout(const unsigned char *bytes, size_t length,
                       size_t *transferred, unsigned long *native_error) {
    errno = 0;
    *native_error = 0;
#ifdef _WIN32
    _set_doserrno(0);
#endif
    *transferred = fwrite(bytes, 1, length, stdout);
    int failure = *transferred == length ? 0 : (errno ? errno : EIO);
    if (fflush(stdout) != 0 && !failure) failure = errno ? errno : EIO;
#ifdef _WIN32
    if (failure) _get_doserrno(native_error);
#endif
    if (failure) clearerr(stdout);
    return failure;
}
