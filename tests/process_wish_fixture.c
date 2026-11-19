/* Controlled Tcl protocol fixture; does not open a GUI or execute Tcl. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <io.h>
#include <fcntl.h>
#include <process.h>
#define process_id _getpid
#else
#include <unistd.h>
#define process_id getpid
#endif
int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--descendant")) {
#ifdef _WIN32
        Sleep(30000);
#else
        sleep(30);
#endif
        return 0;
    }
#ifdef _WIN32
    _setmode(_fileno(stdin), _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);
#endif
    if (argc != 2) return 11;
    FILE *script = fopen(argv[1], "rb");
    if (!script) return 12;
    fclose(script);
    const char *log = getenv("SIGMA_PROCESS_FIXTURE_LOG");
    if (!log) return 13;
    FILE *output = fopen(log, "ab");
    if (!output) return 14;
    fprintf(output, "%ld|%s\n", (long)process_id(), argv[1]);
    if (getenv("SIGMA_PROCESS_FIXTURE_DESCENDANT")) {
#ifdef _WIN32
        wchar_t executable[32768], command[32768];
        if (!GetModuleFileNameW(NULL, executable, 32768)) return 16;
        if (swprintf(command, 32768, L"\"%ls\" --descendant", executable) < 0) return 17;
        STARTUPINFOW startup = {sizeof(startup)};
        PROCESS_INFORMATION child;
        if (!CreateProcessW(executable, command, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &startup, &child)) return 18;
        fprintf(output, "descendant|%lu\n", (unsigned long)child.dwProcessId);
        CloseHandle(child.hThread); CloseHandle(child.hProcess);
#else
        pid_t child = fork();
        if (child < 0) return 18;
        if (!child) { close(0); close(1); close(2); sleep(30); _exit(0); }
        fprintf(output, "descendant|%ld\n", (long)child);
#endif
    }
    fclose(output);
    char header[64], bytes[4096];
    while (fgets(header, sizeof(header), stdin)) {
        unsigned long long left = strtoull(header, NULL, 10);
        while (left) {
            size_t wanted = left < sizeof(bytes) ? (size_t)left : sizeof(bytes);
            size_t count = fread(bytes, 1, wanted, stdin);
            if (!count) return 15;
            left -= count;
        }
        fputs("R 0 0\n", stdout);
        fflush(stdout);
    }
    return 0;
}
