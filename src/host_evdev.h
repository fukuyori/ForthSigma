/* Linux UAPI and libc only, for the static-musl gamepad snapshot backend. */
#include <linux/input.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <time.h>
#include <errno.h>
#include <stdlib.h>
enum {
    SIGMA_EVDEV_KEYS = EVIOCGBIT(EV_KEY, 96),
    SIGMA_EVDEV_ABS = EVIOCGBIT(EV_ABS, 8),
    SIGMA_EVDEV_STATE = EVIOCGKEY(96),
    SIGMA_EVDEV_NAME = EVIOCGNAME(128),
    SIGMA_EVDEV_ID = EVIOCGID,
    SIGMA_EVDEV_ABS0 = EVIOCGABS(0)
};
