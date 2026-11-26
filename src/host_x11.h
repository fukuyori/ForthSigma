/* The Linux libc ABI used by the X11 wire transport; no X11 headers/libraries. */
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <pthread.h>
int sigma_x11_authority_file(int fd);
/* Linux extension, also needed when translate-c omits _GNU_SOURCE. */
int pipe2(int pipefd[2], int flags);

#include <signal.h>
