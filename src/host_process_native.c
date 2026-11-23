/* Runtime process ownership. All creation calls are serialized by the VM owner.
 * The opaque object retains partially-created resources on every error path. */
#define _GNU_SOURCE 1
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif
#include "host_process_native.h"
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#ifdef SIGMA_PROC_TESTING
static unsigned fault_target, fault_seen;
void sigma_proc_test_fault(unsigned step) { fault_target = step; fault_seen = 0; }
static int checkpoint(void) { return fault_target && ++fault_seen == fault_target; }
#else
static int checkpoint(void) { return 0; }
#endif
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <io.h>
#include <fcntl.h>
struct sigma_process {
    HANDLE process, job, thread, child[3], parent[3];
    int parent_fd[3];
    void *attributes;
    int attributes_ready, assigned;
    FILE *streams[3];
    uint32_t state, code;
};
static int win_error(void) {
    switch (GetLastError()) {
        case ERROR_FILE_NOT_FOUND: case ERROR_PATH_NOT_FOUND: return ENOENT;
        case ERROR_DIRECTORY: return ENOTDIR;
        case ERROR_ACCESS_DENIED: case ERROR_SHARING_VIOLATION: return EACCES;
        case ERROR_INVALID_HANDLE: return EBADF;
        case ERROR_NOT_ENOUGH_MEMORY: case ERROR_OUTOFMEMORY: return ENOMEM;
        case ERROR_BAD_EXE_FORMAT: case ERROR_EXE_MACHINE_TYPE_MISMATCH: return ENOEXEC;
        case ERROR_INVALID_PARAMETER: case ERROR_INVALID_NAME: return EINVAL;
        case ERROR_BROKEN_PIPE: case ERROR_NO_DATA: return EPIPE;
        case ERROR_OPERATION_ABORTED: return EINTR;
        default: return EIO;
    }
}
int sigma_proc_check_cwd_windows(const wchar_t *path) {
    DWORD attributes = GetFileAttributesW(path);
    if (attributes == INVALID_FILE_ATTRIBUTES) return win_error();
    return attributes & FILE_ATTRIBUTE_DIRECTORY ? 0 : ENOTDIR;
}
int sigma_proc_probe_windows(const wchar_t *path, int *result) {
    DWORD attributes = GetFileAttributesW(path);
    if (attributes == INVALID_FILE_ATTRIBUTES) {
        int error = win_error();
        if (error == ENOENT || error == ENOTDIR) { *result = 0; return 0; }
        if (error == EACCES) { *result = 1; return 0; }
        return error;
    }
    if (attributes & FILE_ATTRIBUTE_DIRECTORY) { *result = 1; return 0; }
    HANDLE file = CreateFileW(path, FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, NULL);
    if (file == INVALID_HANDLE_VALUE) {
        int error = win_error(); if (error == EACCES) { *result = 1; return 0; } return error;
    }
    DWORD type = GetFileType(file);
    if (!CloseHandle(file)) return win_error();
    if (type != FILE_TYPE_DISK) { *result = 3; return 0; }
    DWORD binary;
    if (!GetBinaryTypeW(path, &binary)) {
        int error = win_error();
        if (error == ENOEXEC) { *result = 3; return 0; }
        if (error == EACCES) { *result = 1; return 0; }
        return error;
    }
    *result = binary == SCS_32BIT_BINARY || binary == SCS_64BIT_BINARY ? 2 : 3;
    return 0;
}
static int close_handle(HANDLE *handle) {
    if (!*handle) return 0;
    if (!CloseHandle(*handle)) return win_error();
    *handle = NULL;
    return 0;
}
static int close_startup(struct sigma_process *p) {
    int error = 0, result;
    for (unsigned i = 0; i < 3; ++i) {
        if ((result = close_handle(&p->child[i])) && !error) error = result;
        if ((result = close_handle(&p->parent[i])) && !error) error = result;
        if (p->parent_fd[i] >= 0) {
            int fd = p->parent_fd[i]; p->parent_fd[i] = -1;
            if (_close(fd) && !error) error = errno ? errno : EIO;
        }
    }
    if ((result = close_handle(&p->thread)) && !error) error = result;
    if (p->attributes) {
        if (p->attributes_ready) DeleteProcThreadAttributeList(p->attributes);
        free(p->attributes); p->attributes = NULL; p->attributes_ready = 0;
    }
    return error;
}
static int duplicate_child(HANDLE source, HANDLE *out) {
    if (!source || source == INVALID_HANDLE_VALUE) return EBADF;
    if (!DuplicateHandle(GetCurrentProcess(), source, GetCurrentProcess(), out, 0, TRUE, DUPLICATE_SAME_ACCESS)) return win_error();
    return 0;
}
static int pipe_stream(struct sigma_process *p, unsigned which) {
    HANDLE reading = NULL, writing = NULL;
    SECURITY_ATTRIBUTES attributes = {sizeof(attributes), NULL, FALSE};
    if (!CreatePipe(&reading, &writing, &attributes, 65536)) return win_error();
    HANDLE parent = which == 0 ? writing : reading;
    HANDLE child = which == 0 ? reading : writing;
    /* Record both handles before any operation that can fail. */
    p->child[which] = child; p->parent[which] = parent;
    errno = 0;
    int fd = _open_osfhandle((intptr_t)parent, _O_BINARY | _O_NOINHERIT | (which == 0 ? _O_WRONLY : _O_RDONLY));
    if (fd < 0) return errno ? errno : EIO;
    p->parent[which] = NULL; p->parent_fd[which] = fd;
    errno = 0;
    p->streams[which] = _fdopen(fd, which == 0 ? "wb" : "rb");
    if (!p->streams[which]) return errno ? errno : EIO;
    p->parent_fd[which] = -1;
    if (setvbuf(p->streams[which], NULL, _IONBF, 0)) return EIO;
    if (!SetHandleInformation(child, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT)) return win_error();
    return 0;
}
static int start_error(struct sigma_process *p, int error) {
    if (p) for (unsigned i = 0; i < 3; ++i) if (p->child[i]) SetHandleInformation(p->child[i], HANDLE_FLAG_INHERIT, 0);
    return error;
}
int sigma_proc_start_windows(struct sigma_process *p, const wchar_t *exe, wchar_t *command, const wchar_t *environment, const wchar_t *cwd, const int modes[3]) {
    if (!p || p->state || p->process || p->job) return EBUSY;
    for (unsigned i = 0; i < 3; ++i) if (p->streams[i] || p->child[i]) return EBUSY;
    for (unsigned i = 0; i < 3; ++i) if (modes[i] < 0 || modes[i] > 3 || (modes[i] == 3 && i != 2)) return EINVAL;
    int error = 0, inherited = 0;
    for (unsigned i = 0; i < 3; ++i) {
        if (modes[i] == 0) error = pipe_stream(p, i);
        else if (modes[i] == 1) {
            inherited = 1;
            error = duplicate_child(GetStdHandle(i == 0 ? STD_INPUT_HANDLE : i == 1 ? STD_OUTPUT_HANDLE : STD_ERROR_HANDLE), &p->child[i]);
        } else if (modes[i] == 2) {
            SECURITY_ATTRIBUTES attributes = {sizeof(attributes), NULL, TRUE};
            HANDLE handle = CreateFileW(L"NUL", i == 0 ? GENERIC_READ : GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, &attributes, OPEN_EXISTING, 0, NULL);
            if (handle == INVALID_HANDLE_VALUE) error = win_error(); else p->child[i] = handle;
        } else error = duplicate_child(p->child[1], &p->child[i]);
        if (error) return start_error(p, error);
        if (checkpoint()) return start_error(p, EIO);
    }
    p->job = CreateJobObjectW(NULL, NULL);
    if (!p->job) return start_error(p, win_error());
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;
    memset(&limits, 0, sizeof(limits));
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_BREAKAWAY_OK;
    if (!SetInformationJobObject(p->job, JobObjectExtendedLimitInformation, &limits, sizeof(limits))) return start_error(p, win_error());
    if (checkpoint()) return start_error(p, EIO);
    SIZE_T bytes = 0;
    InitializeProcThreadAttributeList(NULL, 1, 0, &bytes);
    if (!bytes) return start_error(p, win_error());
    p->attributes = malloc(bytes);
    if (!p->attributes) return start_error(p, ENOMEM);
    if (!InitializeProcThreadAttributeList(p->attributes, 1, 0, &bytes)) return start_error(p, win_error());
    p->attributes_ready = 1;
    if (!UpdateProcThreadAttribute(p->attributes, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, p->child, sizeof(p->child), NULL, NULL)) return start_error(p, win_error());
    if (checkpoint()) return start_error(p, EIO);
    STARTUPINFOEXW startup;
    memset(&startup, 0, sizeof(startup));
    startup.StartupInfo.cb = sizeof(startup);
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup.StartupInfo.hStdInput = p->child[0]; startup.StartupInfo.hStdOutput = p->child[1]; startup.StartupInfo.hStdError = p->child[2];
    startup.lpAttributeList = p->attributes;
    PROCESS_INFORMATION information;
    memset(&information, 0, sizeof(information));
    DWORD flags = CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT | CREATE_NEW_PROCESS_GROUP | EXTENDED_STARTUPINFO_PRESENT;
    if (!inherited) flags |= CREATE_NO_WINDOW;
    if (!CreateProcessW(exe, command, NULL, NULL, TRUE, flags, (void *)environment, cwd, &startup.StartupInfo, &information)) return start_error(p, win_error());
    p->process = information.hProcess; p->thread = information.hThread; p->state = 1;
    if (checkpoint()) return start_error(p, EIO);
    if (!AssignProcessToJobObject(p->job, p->process)) return start_error(p, win_error());
    p->assigned = 1;
    if (checkpoint()) return start_error(p, EIO);
    if (ResumeThread(p->thread) == (DWORD)-1) return start_error(p, win_error());
    if (checkpoint()) return start_error(p, EIO);
    error = close_startup(p);
    return error ? start_error(p, error) : 0;
}
int sigma_proc_status(struct sigma_process *p, uint32_t *state, uint32_t *code) {
    if (!p) return EINVAL;
    if (p->state == 1) {
        DWORD result = WaitForSingleObject(p->process, 0);
        if (result == WAIT_FAILED) return win_error();
        if (result == WAIT_OBJECT_0) {
            DWORD exited;
            if (!GetExitCodeProcess(p->process, &exited)) return win_error();
            p->state = 2; p->code = exited;
        }
    }
    *state = p->state; *code = p->code;
    return 0;
}
int sigma_proc_signal(struct sigma_process *p, int force) {
    if (!p) return EINVAL;
    if (p->assigned && p->job) return TerminateJobObject(p->job, force ? 137 : 143) ? 0 : win_error();
    if (!p->process) return EINVAL;
    if (TerminateProcess(p->process, force ? 137 : 143)) return 0;
    int error = win_error();
    /* Startup rollback may encounter an unassigned process that already died. */
    if (WaitForSingleObject(p->process, 0) == WAIT_OBJECT_0) return 0;
    return error;
}
int sigma_proc_wait_slice(struct sigma_process *p, unsigned ms) {
    if (!p || !p->process || p->state != 1) return 0;
    DWORD result = WaitForSingleObject(p->process, ms);
    return result == WAIT_OBJECT_0 || result == WAIT_TIMEOUT ? 0 : win_error();
}
static void pause_ms(unsigned ms) { Sleep(ms); }
static int now_ms(uint64_t *out) { *out = GetTickCount64(); return 0; }
#else
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <pthread.h>
#include <sys/wait.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <time.h>
#ifdef __linux__
#include <sys/syscall.h>
#include <dirent.h>
#else
#include <spawn.h>
#endif
struct sigma_process {
    pid_t pid;
    int child[3], lost, lost_reported, group_ready;
    FILE *streams[3];
    uint32_t state, code;
};
int sigma_proc_check_cwd_posix(const char *path) {
    struct stat info; if (stat(path, &info)) return errno;
    if (!S_ISDIR(info.st_mode)) return ENOTDIR;
    return access(path, X_OK) ? errno : 0;
}
int sigma_proc_probe_posix(const char *path, int *result) {
    struct stat info;
    if (stat(path, &info)) {
        if (errno == ENOENT || errno == ENOTDIR) { *result = 0; return 0; }
        if (errno == EACCES) { *result = 1; return 0; }
        return errno;
    }
    if (!S_ISREG(info.st_mode)) { *result = 1; return 0; }
    if (access(path, X_OK)) {
        if (errno == EACCES) { *result = 1; return 0; }
        return errno;
    }
    *result = 2; return 0;
}
static int move_above_stdio(int fd) {
    if (fd > 2) return fd;
    int moved = fcntl(fd, F_DUPFD_CLOEXEC, 3);
    int error = errno;
    close(fd); errno = error;
    return moved;
}
static int close_startup(struct sigma_process *p) {
    int error = 0;
    for (unsigned i = 0; i < 3; ++i) if (p->child[i] >= 0) {
        if (close(p->child[i]) && !error) error = errno ? errno : EIO;
        /* close(EINTR) is not retried: the fd may already have been released. */
        p->child[i] = -1;
    }
    return error;
}
static int make_pipe(int fds[2]) {
#ifdef __linux__
    if (pipe2(fds, O_CLOEXEC)) return errno;
#else
    if (pipe(fds)) return errno;
    if (fcntl(fds[0], F_SETFD, FD_CLOEXEC) < 0 || fcntl(fds[1], F_SETFD, FD_CLOEXEC) < 0) {
        int error = errno; close(fds[0]); close(fds[1]); return error;
    }
#endif
    fds[0] = move_above_stdio(fds[0]);
    if (fds[0] < 0) { int error = errno; close(fds[1]); return error; }
    fds[1] = move_above_stdio(fds[1]);
    if (fds[1] < 0) { int error = errno; close(fds[0]); return error; }
    return 0;
}
static int prepare_stdio(struct sigma_process *p, const int modes[3]) {
    for (unsigned i = 0; i < 3; ++i) {
        if (modes[i] == 0) {
            int fds[2]; int error = make_pipe(fds); if (error) return error;
            int parent = fds[i == 0 ? 1 : 0]; p->child[i] = fds[i == 0 ? 0 : 1];
            p->streams[i] = fdopen(parent, i == 0 ? "wb" : "rb");
            if (!p->streams[i]) { error = errno; close(parent); return error; }
            if (setvbuf(p->streams[i], NULL, _IONBF, 0)) return EIO;
        } else if (modes[i] == 1 || modes[i] == 3) {
            int source = modes[i] == 3 ? p->child[1] : (int)i;
            p->child[i] = fcntl(source, F_DUPFD_CLOEXEC, 3);
            if (p->child[i] < 0) return errno;
        } else {
            int fd = open("/dev/null", (i == 0 ? O_RDONLY : O_WRONLY) | O_CLOEXEC);
            if (fd < 0) return errno;
            p->child[i] = move_above_stdio(fd);
            if (p->child[i] < 0) return errno;
        }
        if (checkpoint()) return EIO;
    }
    return 0;
}
static void default_signals(sigset_t *defaults) {
    sigemptyset(defaults);
    sigaddset(defaults, SIGINT); sigaddset(defaults, SIGQUIT); sigaddset(defaults, SIGTERM);
    sigaddset(defaults, SIGHUP); sigaddset(defaults, SIGPIPE); sigaddset(defaults, SIGCHLD);
}
#ifdef __APPLE__
int sigma_display_probe_spawnattr(posix_spawnattr_t *attributes) {
    struct sigaction child_status;
    if (sigaction(SIGCHLD, NULL, &child_status)) return errno;
    if (child_status.sa_handler == SIG_IGN || (child_status.sa_flags & SA_NOCLDWAIT)) return ECHILD;

    sigset_t defaults, mask;
    sigemptyset(&mask);
    sigemptyset(&defaults);
    const int signals[] = {SIGINT, SIGQUIT, SIGTERM, SIGHUP, SIGPIPE, SIGCHLD};
    for (unsigned i = 0; i < sizeof(signals) / sizeof(signals[0]); ++i) sigaddset(&defaults, signals[i]);

    int error = posix_spawnattr_setflags(attributes, POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK);
    if (!error) error = posix_spawnattr_setpgroup(attributes, 0);
    if (!error) error = posix_spawnattr_setsigdefault(attributes, &defaults);
    if (!error) error = posix_spawnattr_setsigmask(attributes, &mask);
    return error;
}
#endif
#ifdef __linux__
static unsigned close_limit(void) {
    struct rlimit limit;
    unsigned high = 65536;
    if (!getrlimit(RLIMIT_NOFILE, &limit) && limit.rlim_max != RLIM_INFINITY) high = limit.rlim_max > INT_MAX ? INT_MAX : (unsigned)limit.rlim_max;
    DIR *directory = opendir("/proc/self/fd");
    if (directory) {
        struct dirent *item;
        while ((item = readdir(directory))) {
            char *end; unsigned long value = strtoul(item->d_name, &end, 10);
            if (!*end && value < INT_MAX && value + 1 > high) high = value + 1;
        }
        closedir(directory);
    }
    return high;
}
static void child_error(int fd, int error) {
    const unsigned char *bytes = (const unsigned char *)&error;
    size_t left = sizeof(error);
    while (left) {
        ssize_t n = write(fd, bytes, left);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) break;
        bytes += n; left -= n;
    }
    _exit(127);
}
static void close_other_fds(int except, unsigned limit) {
    int fallback = 0;
#ifdef SYS_close_range
    if (except > 3 && syscall(SYS_close_range, 3U, (unsigned)except - 1, 0U)) fallback = 1;
    if (syscall(SYS_close_range, (unsigned)except + 1, ~0U, 0U)) fallback = 1;
#else
    fallback = 1;
#endif
    if (fallback) for (unsigned fd = 3; fd < limit; ++fd) if (fd != (unsigned)except) close((int)fd);
}
#endif
int sigma_proc_start_posix(struct sigma_process *p, const char *exe, char *const *argv, char *const *environment, const char *cwd, const int modes[3]) {
    if (!p || p->state || p->pid) return EBUSY;
    for (unsigned i = 0; i < 3; ++i) if (p->streams[i] || p->child[i] >= 0) return EBUSY;
    for (unsigned i = 0; i < 3; ++i) if (modes[i] < 0 || modes[i] > 3 || (modes[i] == 3 && i != 2)) return EINVAL;
    struct sigaction disposition;
    if (sigaction(SIGCHLD, NULL, &disposition)) return errno;
    if (disposition.sa_handler == SIG_IGN || (disposition.sa_flags & SA_NOCLDWAIT)) return ECHILD;
    int error = prepare_stdio(p, modes); if (error) return error;
    sigset_t mask, defaults; sigemptyset(&mask); default_signals(&defaults);
#ifdef __linux__
    int errors[2]; error = make_pipe(errors); if (error) return error;
    unsigned limit = close_limit();
    sigset_t all, previous;
    sigfillset(&all);
    error = pthread_sigmask(SIG_SETMASK, &all, &previous);
    if (error) { close(errors[0]); close(errors[1]); return error; }
    pid_t pid = fork();
    if (pid < 0) {
        error = errno; pthread_sigmask(SIG_SETMASK, &previous, NULL);
        close(errors[0]); close(errors[1]); return error;
    }
    if (pid == 0) {
        if (setpgid(0, 0)) child_error(errors[1], errno);
        struct sigaction action; memset(&action, 0, sizeof(action)); sigemptyset(&action.sa_mask); action.sa_handler = SIG_DFL;
        int signals[] = {SIGINT, SIGQUIT, SIGTERM, SIGHUP, SIGPIPE, SIGCHLD};
        for (unsigned i = 0; i < sizeof(signals)/sizeof(signals[0]); ++i) if (sigaction(signals[i], &action, NULL)) child_error(errors[1], errno);
        if (chdir(cwd)) child_error(errors[1], errno);
        for (unsigned i = 0; i < 3; ++i) if (dup2(p->child[i], (int)i) < 0) child_error(errors[1], errno);
        close_other_fds(errors[1], limit);
        if (sigprocmask(SIG_SETMASK, &mask, NULL)) child_error(errors[1], errno);
        execve(exe, argv, environment);
        child_error(errors[1], errno);
    }
    p->pid = pid; p->state = 1;
    error = pthread_sigmask(SIG_SETMASK, &previous, NULL);
    if (error) { close(errors[0]); close(errors[1]); return error; }
    /* Child also does setpgid, before any user program can execute. */
    if (setpgid(pid, pid) && errno != EACCES && errno != ESRCH) { error = errno; close(errors[0]); close(errors[1]); return error; }
    p->group_ready = 1;
    if (checkpoint()) { close(errors[0]); close(errors[1]); return EIO; }
    close(errors[1]);
    int startup_error = 0; size_t received = 0;
    while (received < sizeof(startup_error)) {
        ssize_t n = read(errors[0], (char *)&startup_error + received, sizeof(startup_error) - received);
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) { error = errno; break; }
        if (!n) break;
        received += (size_t)n;
    }
    close(errors[0]);
    if (error) return error;
    if (received) return received == sizeof(startup_error) ? startup_error : EIO;
#else
    posix_spawn_file_actions_t actions; posix_spawnattr_t attributes;
    error = posix_spawn_file_actions_init(&actions); if (error) return error;
    error = posix_spawnattr_init(&attributes);
    if (error) { posix_spawn_file_actions_destroy(&actions); return error; }
    for (unsigned i = 0; i < 3 && !error; ++i) error = posix_spawn_file_actions_adddup2(&actions, p->child[i], (int)i);
    for (unsigned i = 0; i < 3 && !error; ++i) error = posix_spawn_file_actions_addclose(&actions, p->child[i]);
    if (!error) error = posix_spawn_file_actions_addchdir_np(&actions, cwd);
    if (!error) error = posix_spawnattr_setflags(&attributes, POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK);
    if (!error) error = posix_spawnattr_setpgroup(&attributes, 0);
    if (!error) error = posix_spawnattr_setsigdefault(&attributes, &defaults);
    if (!error) error = posix_spawnattr_setsigmask(&attributes, &mask);
    pid_t pid = 0;
    if (!error) error = posix_spawn(&pid, exe, &actions, &attributes, argv, environment);
    posix_spawnattr_destroy(&attributes); posix_spawn_file_actions_destroy(&actions);
    if (error) return error;
    p->pid = pid; p->state = 1; p->group_ready = 1;
#endif
    if (checkpoint()) return EIO;
    return close_startup(p);
}
int sigma_proc_status(struct sigma_process *p, uint32_t *state, uint32_t *code) {
    if (!p) return EINVAL;
    if (p->lost) return ECHILD;
    /* Revalidate even cached terminal results before signaling their PGID. */
    if (p->pid) {
        siginfo_t info; memset(&info, 0, sizeof(info));
        if (waitid(P_PID, (id_t)p->pid, &info, WEXITED | WNOHANG | WNOWAIT)) {
            if (errno == ECHILD) p->lost = 1;
            return errno;
        }
        if (info.si_pid && p->state == 1) {
            if (info.si_code != CLD_EXITED && info.si_code != CLD_KILLED && info.si_code != CLD_DUMPED) return EIO;
            p->state = info.si_code == CLD_EXITED ? 2 : 3;
            p->code = (uint32_t)(info.si_code == CLD_EXITED ? info.si_status & 0xff : info.si_status);
        }
    }
    *state = p->state; *code = p->code;
    return 0;
}
int sigma_proc_signal(struct sigma_process *p, int force) {
    if (!p) return EINVAL;
    if (p->lost) return ECHILD;
    if (!p->pid) return EINVAL;
    uint32_t state, code; int error = sigma_proc_status(p, &state, &code);
    if (error) return error;
    int sig = force ? SIGKILL : SIGTERM;
    if (kill(-p->pid, sig)) {
        int group_error = errno;
        /* A failed launch can return before the child established its new group.
           Some hosts also deny signaling a process group while allowing its
           owned child PID, so retain a direct-child cleanup path on EPERM. */
        if (group_error != ESRCH && group_error != EPERM && p->group_ready) return group_error;
        if (group_error != ESRCH && kill(p->pid, sig) && errno != ESRCH) return errno;
    }
    return 0;
}
static void pause_ms(unsigned ms) {
    struct timespec time = {(time_t)(ms / 1000), (long)(ms % 1000) * 1000000};
    while (nanosleep(&time, &time) && errno == EINTR) {}
}
int sigma_proc_wait_slice(struct sigma_process *p, unsigned ms) {
    if (!p || !p->pid || p->state != 1) return 0;
    struct timespec time = {(time_t)(ms / 1000), (long)(ms % 1000) * 1000000};
    if (nanosleep(&time, NULL) && errno != EINTR) return errno;
    return 0;
}
static int now_ms(uint64_t *out) {
    struct timespec time; if (clock_gettime(CLOCK_MONOTONIC, &time)) return errno ? errno : EIO;
    *out = (uint64_t)time.tv_sec * 1000 + (uint64_t)time.tv_nsec / 1000000;
    return 0;
}
#endif
struct sigma_process *sigma_proc_new(void) {
    struct sigma_process *p = calloc(1, sizeof(*p));
    if (p) for (unsigned i = 0; i < 3; ++i) {
#ifdef _WIN32
        p->parent_fd[i] = -1;
#else
        p->child[i] = -1;
#endif
    }
    return p;
}
FILE *sigma_proc_stream(struct sigma_process *p, unsigned which) { return p && which < 3 ? p->streams[which] : NULL; }
FILE *sigma_proc_take_stream(struct sigma_process *p, unsigned which) {
    FILE *stream = sigma_proc_stream(p, which); if (stream) p->streams[which] = NULL; return stream;
}
int sigma_proc_destroy(struct sigma_process *p) {
    if (!p) return 0;
    uint32_t state = p->state, code = p->code;
    int error = sigma_proc_status(p, &state, &code);
#ifdef _WIN32
    if (error) {
        /* Independent streams can still be released, but keep unknown process ownership. */
        close_startup(p);
        for (unsigned i = 0; i < 3; ++i) if (p->streams[i]) { FILE *f = p->streams[i]; p->streams[i] = NULL; fclose(f); }
        return error;
    }
#else
    int lost_error = 0;
    if (error) {
        if (!p->lost) return error;
        /* The old PID is no longer ours. Never signal/reap its numerical replacement. */
        p->pid = 0;
        if (!p->lost_reported) { lost_error = ECHILD; p->lost_reported = 1; }
    }
#endif
    if (!error && state == 1) return EBUSY;
    error = close_startup(p);
    for (unsigned i = 0; i < 3; ++i) if (p->streams[i]) {
        FILE *stream = p->streams[i]; p->streams[i] = NULL;
        if (fclose(stream) && !error) error = errno ? errno : EIO;
    }
#ifdef _WIN32
    int result = close_handle(&p->process); if (result && !error) error = result;
    result = close_handle(&p->job); if (result && !error) error = result;
#else
    if (p->pid) {
        pid_t result;
        do { result = waitpid(p->pid, NULL, 0); } while (result < 0 && errno == EINTR);
        if (result < 0) { if (errno == ECHILD) p->lost = 1; if (!error) error = errno; } else p->pid = 0;
    }
    if (!error) error = lost_error;
#endif
    if (error) return error;
    free(p); return 0;
}
int sigma_proc_abort(struct sigma_process *p, unsigned timeout_ms) {
    if (!p) return 0;
#ifdef _WIN32
    int started = p->process != NULL || (p->assigned && p->job);
#else
    if (p->lost) return sigma_proc_destroy(p);
    int started = p->pid != 0;
#endif
    if (started) {
        int error = sigma_proc_signal(p, 1); if (error) return error;
        uint64_t start;
        error = now_ms(&start); if (error) return error;
        for (;;) {
            uint32_t state, code; error = sigma_proc_status(p, &state, &code); if (error) return error;
            if (state != 1) break;
            uint64_t current;
            error = now_ms(&current); if (error) return error;
            if (current - start >= timeout_ms) return EBUSY;
            pause_ms(1);
        }
    }
    return sigma_proc_destroy(p);
}
#ifdef SIGMA_PROC_TESTING
uint64_t sigma_proc_test_pid(struct sigma_process *p) {
#ifdef _WIN32
    return p && p->process ? GetProcessId(p->process) : 0;
#else
    return p ? (uint64_t)p->pid : 0;
#endif
}
intptr_t sigma_proc_test_read(struct sigma_process *p, unsigned which, void *bytes, size_t length) {
    FILE *stream = sigma_proc_stream(p, which); if (!stream) return -1;
    size_t n = fread(bytes, 1, length, stream); return n ? (intptr_t)n : ferror(stream) ? -1 : 0;
}
intptr_t sigma_proc_test_write(struct sigma_process *p, const void *bytes, size_t length) {
    FILE *stream = sigma_proc_stream(p, 0); if (!stream) return -1;
    size_t n = fwrite(bytes, 1, length, stream); return n == length ? (intptr_t)n : -1;
}
int sigma_proc_test_close(struct sigma_process *p, unsigned which) {
    FILE *stream = sigma_proc_take_stream(p, which); return stream ? fclose(stream) : 0;
}
#endif
