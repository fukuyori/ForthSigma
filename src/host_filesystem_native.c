/* Filesystem extension: OS layouts and owned canonical paths stay in the host. */
#define _GNU_SOURCE 1
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <stdio.h>
#include <limits.h>
int sigma_fs_name_too_long(void) { return ENAMETOOLONG; }
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <io.h>
#include <wchar.h>
#ifdef SIGMA_FS_TESTING
static unsigned open_attempts;
unsigned sigma_fs_test_opens(void) { return open_attempts; }
#endif
static int win_error(void) {
    switch (GetLastError()) {
    case ERROR_FILE_NOT_FOUND: case ERROR_PATH_NOT_FOUND: case ERROR_INVALID_DRIVE:
    case ERROR_BAD_NETPATH: case ERROR_BAD_NET_NAME: return ENOENT;
    case ERROR_ACCESS_DENIED: case ERROR_SHARING_VIOLATION: return EACCES;
    case ERROR_INVALID_HANDLE: return EBADF;
    case ERROR_NOT_ENOUGH_MEMORY: case ERROR_OUTOFMEMORY: return ENOMEM;
    case ERROR_DIRECTORY: return ENOTDIR;
    case ERROR_INVALID_NAME: case ERROR_INVALID_PARAMETER: return EINVAL;
    case ERROR_FILENAME_EXCED_RANGE: return ENAMETOOLONG;
    case ERROR_CANT_RESOLVE_FILENAME: return ELOOP;
    default: return EIO;
    }
}
static int pipe_share(const wchar_t *p) {
    const wchar_t *share = wcschr(p, L'\\');
    if (!share) return 0;
    ++share;
    return _wcsnicmp(share, L"pipe", 4) == 0 && (!share[4] || share[4] == L'\\');
}
static int expanded_device(const wchar_t *path) {
    DWORD capacity = 256;
    wchar_t *full = NULL;
    int result = 0;
    for (;;) {
        wchar_t *next = realloc(full, (size_t)capacity * sizeof(*full));
        if (!next) { result = ENOMEM; break; }
        full = next;
        DWORD count = GetFullPathNameW(path, capacity, full, NULL);
        if (!count) { result = win_error(); break; }
        if (count >= capacity) {
            if (count == UINT32_MAX) { result = ENAMETOOLONG; break; }
            capacity = count + 1;
            continue;
        }
        if (wcsncmp(full, L"\\\\.\\", 4) == 0) result = EINVAL;
        break;
    }
    free(full);
    return result;
}
static int wide_name(const char *name, wchar_t **out) {
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name, -1, NULL, 0);
    if (!count) return EILSEQ;
    wchar_t *p = malloc((size_t)count * sizeof(*p));
    if (!p) return ENOMEM;
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name, -1, p, count)) { free(p); return EILSEQ; }
    for (int i = 0; i < count; ++i) if (p[i] == L'/') p[i] = L'\\';
    int refused = 0;
    if (wcsncmp(p, L"\\\\.\\", 4) == 0 || wcsncmp(p, L"\\??\\", 4) == 0) refused = 1;
    else if (wcsncmp(p, L"\\\\?\\", 4) == 0) {
        if (_wcsnicmp(p + 4, L"UNC\\", 4) == 0) refused = pipe_share(p + 8);
        else refused = !(wcslen(p) >= 7 && p[5] == L':' && p[6] == L'\\');
    } else if (wcsncmp(p, L"\\\\", 2) == 0) refused = pipe_share(p + 2);
    if (refused) { free(p); return EINVAL; }
    int error = expanded_device(p);
    if (error) { free(p); return error; }
    *out = p;
    return 0;
}
static int open_name(const char *name, HANDLE *out) {
    wchar_t *wide = NULL;
    int error = wide_name(name, &wide);
    if (error) return error;
#ifdef SIGMA_FS_TESTING
    ++open_attempts;
#endif
    HANDLE h = CreateFileW(wide, 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                          NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
    error = h == INVALID_HANDLE_VALUE ? win_error() : 0;
    free(wide);
    if (!error) *out = h;
    return error;
}
int sigma_fs_realpath(const char *name, char **out, size_t *length) {
    HANDLE h;
    int error = open_name(name, &h);
    if (error) return error;
    DWORD capacity = 256;
    wchar_t *wide = NULL;
    char *result = NULL;
    for (;;) {
        wchar_t *next = realloc(wide, (size_t)capacity * sizeof(*wide));
        if (!next) { error = ENOMEM; break; }
        wide = next;
        DWORD count = GetFinalPathNameByHandleW(h, wide, capacity, FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
        if (!count) { error = win_error(); break; }
        if (count >= capacity) {
            if (count == UINT32_MAX) { error = ENAMETOOLONG; break; }
            capacity = count + 1;
            continue;
        }
        if (count > INT_MAX) { error = ENAMETOOLONG; break; }
        int bytes = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, (int)count, NULL, 0, NULL, NULL);
        if (!bytes) { error = EILSEQ; break; }
        result = malloc((size_t)bytes + 1);
        if (!result) { error = ENOMEM; break; }
        if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, (int)count, result, bytes, NULL, NULL)) { error = EILSEQ; break; }
        result[bytes] = 0;
        *length = (size_t)bytes;
        break;
    }
    free(wide);
    if (!CloseHandle(h) && !error) error = win_error();
    if (error) free(result); else *out = result;
    return error;
}
int sigma_fs_info(const char *name, uint64_t *size, int64_t *seconds, uint32_t *nanoseconds) {
    HANDLE h;
    int error = open_name(name, &h);
    if (error) return error;
    BY_HANDLE_FILE_INFORMATION info;
    if (GetFileType(h) != FILE_TYPE_DISK) error = EINVAL;
    else if (!GetFileInformationByHandle(h, &info)) error = win_error();
    else if (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) error = EINVAL;
    else {
        uint64_t ticks = ((uint64_t)info.ftLastWriteTime.dwHighDateTime << 32) | info.ftLastWriteTime.dwLowDateTime;
        *size = ((uint64_t)info.nFileSizeHigh << 32) | info.nFileSizeLow;
        *seconds = (int64_t)(ticks / 10000000) - INT64_C(11644473600);
        *nanoseconds = (uint32_t)(ticks % 10000000) * 100;
    }
    if (!CloseHandle(h) && !error) error = win_error();
    return error;
}
int sigma_fs_regular(int fd) {
    HANDLE h = (HANDLE)_get_osfhandle(fd);
    if (h == INVALID_HANDLE_VALUE) return EBADF;
    if (GetFileType(h) != FILE_TYPE_DISK) return EINVAL;
    BY_HANDLE_FILE_INFORMATION info;
    if (!GetFileInformationByHandle(h, &info)) return win_error();
    return info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY ? EINVAL : 0;
}
int sigma_fs_sync(int fd) {
    return FlushFileBuffers((HANDLE)_get_osfhandle(fd)) ? 0 : win_error();
}
#else
#include <sys/stat.h>
#include <unistd.h>
int sigma_fs_realpath(const char *name, char **out, size_t *length) {
    char *result = realpath(name, NULL);
    if (!result) return errno ? errno : EIO;
    *length = strlen(result);
    *out = result;
    return 0;
}
int sigma_fs_info(const char *name, uint64_t *size, int64_t *seconds, uint32_t *nanoseconds) {
    struct stat info;
    if (stat(name, &info)) return errno ? errno : EIO;
    if (!S_ISREG(info.st_mode) || info.st_size < 0) return EINVAL;
    *size = (uint64_t)info.st_size;
#ifdef __APPLE__
    *seconds = info.st_mtimespec.tv_sec;
    *nanoseconds = (uint32_t)info.st_mtimespec.tv_nsec;
#else
    *seconds = info.st_mtim.tv_sec;
    *nanoseconds = (uint32_t)info.st_mtim.tv_nsec;
#endif
    return 0;
}
int sigma_fs_regular(int fd) {
    struct stat info;
    if (fstat(fd, &info)) return errno ? errno : EIO;
    return S_ISREG(info.st_mode) ? 0 : EINVAL;
}
int sigma_fs_sync(int fd) { return fsync(fd) == 0 ? 0 : (errno ? errno : EIO); }
#endif
void sigma_fs_free(char *bytes) { free(bytes); }
