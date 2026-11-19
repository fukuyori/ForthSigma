#ifndef SIGMA_PROCESS_NATIVE_H
#define SIGMA_PROCESS_NATIVE_H
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#ifdef _WIN32
#include <wchar.h>
#ifdef SIGMA_PROC_TESTING
#define PROC_API __declspec(dllexport)
#else
#define PROC_API
#endif
#else
#define PROC_API
#endif
struct sigma_process;
PROC_API struct sigma_process *sigma_proc_new(void);
#ifdef _WIN32
PROC_API int sigma_proc_check_cwd_windows(const wchar_t *);
PROC_API int sigma_proc_probe_windows(const wchar_t *, int *);
PROC_API int sigma_proc_start_windows(struct sigma_process *, const wchar_t *, wchar_t *, const wchar_t *, const wchar_t *, const int modes[3]);
#else
PROC_API int sigma_proc_check_cwd_posix(const char *);
PROC_API int sigma_proc_probe_posix(const char *, int *);
PROC_API int sigma_proc_start_posix(struct sigma_process *, const char *, char *const *, char *const *, const char *, const int modes[3]);
#endif
PROC_API int sigma_proc_status(struct sigma_process *, uint32_t *state, uint32_t *code);
PROC_API int sigma_proc_signal(struct sigma_process *, int force);
PROC_API int sigma_proc_wait_slice(struct sigma_process *, unsigned);
/* Destroy only a terminal process; failure retains the object for retry. */
PROC_API int sigma_proc_destroy(struct sigma_process *);
/* Kill the owned group/job and drain only process termination, never pipe data. */
PROC_API int sigma_proc_abort(struct sigma_process *, unsigned timeout_ms);
PROC_API FILE *sigma_proc_stream(struct sigma_process *, unsigned);
PROC_API FILE *sigma_proc_take_stream(struct sigma_process *, unsigned);
#ifdef SIGMA_PROC_TESTING
PROC_API void sigma_proc_test_fault(unsigned);
PROC_API uint64_t sigma_proc_test_pid(struct sigma_process *);
PROC_API intptr_t sigma_proc_test_read(struct sigma_process *, unsigned, void *, size_t);
PROC_API intptr_t sigma_proc_test_write(struct sigma_process *, const void *, size_t);
PROC_API int sigma_proc_test_close(struct sigma_process *, unsigned);
#endif
#endif
