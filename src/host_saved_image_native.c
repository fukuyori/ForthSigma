/* Saved executable publication: private temporary stream, then atomic rename. */
#define _GNU_SOURCE 1
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <stdatomic.h>
#include <sys/stat.h>
#include <fcntl.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <io.h>
static wchar_t *wide_path(const char *path) {
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
    if (!n) return NULL;
    wchar_t *out = malloc((size_t)n * sizeof(*out));
    if (!out) return NULL;
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, out, n)) { free(out); return NULL; }
    return out;
}
static unsigned long process_id(void) { return GetCurrentProcessId(); }
int sigma_saved_target_safe(FILE *source, const char *path) {
    wchar_t *wide = wide_path(path);
    if (!wide) return 0;
    DWORD attr = GetFileAttributesW(wide);
    if (attr == INVALID_FILE_ATTRIBUTES) {
        DWORD error = GetLastError(); free(wide);
        return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND;
    }
    /* Reject a final reparse point; publication never follows or replaces links. */
    if (attr & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY)) { free(wide); return 0; }
    HANDLE target = CreateFileW(wide, FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, NULL);
    free(wide);
    if (target == INVALID_HANDLE_VALUE) return 0;
    BY_HANDLE_FILE_INFORMATION a, b;
    HANDLE original = (HANDLE)_get_osfhandle(_fileno(source));
    int ok = GetFileInformationByHandle(original, &a) && GetFileInformationByHandle(target, &b);
    CloseHandle(target);
    if (!ok) return 0;
    return !(a.dwVolumeSerialNumber == b.dwVolumeSerialNumber && a.nFileIndexHigh == b.nFileIndexHigh && a.nFileIndexLow == b.nFileIndexLow);
}
#else
#include <unistd.h>
static unsigned long process_id(void) { return (unsigned long)getpid(); }
int sigma_saved_target_safe(FILE *source, const char *path) {
    struct stat a, b;
    if (fstat(fileno(source), &a)) return 0;
    if (lstat(path, &b)) return errno == ENOENT;
    if (S_ISLNK(b.st_mode) || !S_ISREG(b.st_mode) || access(path, W_OK) != 0) return 0;
    return !(a.st_dev == b.st_dev && a.st_ino == b.st_ino);
}
#endif
static _Atomic unsigned long sequence;
FILE *sigma_saved_temp(const char *target, char *name, size_t capacity, unsigned *final_mode) {
    const char *last = strrchr(target, '/');
#ifdef _WIN32
    const char *back = strrchr(target, '\\');
    if (back && (!last || back > last)) last = back;
#endif
    size_t prefix = last ? (size_t)(last - target + 1) : 0;
#ifdef _WIN32
    if (!last && target[0] && target[1] == ':') prefix = 2;
#endif
    if (prefix >= capacity) return NULL;
    *final_mode = 0;
    for (unsigned attempt = 0; attempt < 64; ++attempt) {
        memcpy(name, target, prefix);
        unsigned long serial = atomic_fetch_add_explicit(&sequence, 1, memory_order_relaxed);
        int n = snprintf(name + prefix, capacity - prefix, ".sigma-save-%lu-%lu.tmp", process_id(), serial);
        if (n < 0 || (size_t)n >= capacity - prefix) return NULL;
#ifdef _WIN32
        wchar_t *wide = wide_path(name);
        if (!wide) return NULL;
        int fd = _wopen(wide, _O_CREAT | _O_EXCL | _O_RDWR | _O_BINARY | _O_NOINHERIT, _S_IREAD | _S_IWRITE);
        free(wide);
        if (fd < 0) { if (errno == EEXIST) continue; return NULL; }
        FILE *stream = _fdopen(fd, "w+b");
        if (!stream) { _close(fd); wide = wide_path(name); if (wide) { _wremove(wide); free(wide); } }
#else
        /* Let the kernel apply umask/default ACLs to the empty exclusive file.
           Capture those permissions, make it private before writing any bytes,
           then restore the captured permissions after the complete footer flush. */
        int fd = open(name, O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC, 0777);
        if (fd < 0) { if (errno == EEXIST) continue; return NULL; }
        struct stat permissions;
        if (fstat(fd, &permissions) || fchmod(fd, 0600)) { close(fd); unlink(name); return NULL; }
        *final_mode = (unsigned)(permissions.st_mode & 0777);
        FILE *stream = fdopen(fd, "w+b");
        if (!stream) { close(fd); unlink(name); }
#endif
        return stream;
    }
    return NULL;
}
int sigma_saved_mode(FILE *stream, unsigned mode) {
#ifdef _WIN32
    (void)stream; (void)mode;
    return 0;
#else
    return fchmod(fileno(stream), (mode_t)mode);
#endif
}
int sigma_saved_publish(FILE *source, const char *name, const char *target) {
    if (!sigma_saved_target_safe(source, target)) return -1;
#ifdef _WIN32
    wchar_t *a = wide_path(name), *b = wide_path(target);
    if (!a || !b) { free(a); free(b); return -1; }
    int ok = MoveFileExW(a, b, MOVEFILE_REPLACE_EXISTING);
    free(a); free(b);
    return ok ? 0 : -1;
#else
    return rename(name, target);
#endif
}
