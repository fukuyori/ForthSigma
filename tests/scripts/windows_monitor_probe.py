"""Read-only Win32 display probes, independent of Sigma's cached enumeration."""
import ctypes as c
from ctypes import wintypes as w
import struct

user = c.WinDLL('user32', use_last_error=True)


class MonitorInfo(c.Structure):
    _fields_ = [('size', w.DWORD), ('rect', w.RECT), ('work', w.RECT),
                ('flags', w.DWORD), ('device', w.WCHAR * 32)]


def xywh(r):
    return [r.left, r.top, r.right - r.left, r.bottom - r.top]


def topology(rows):
    """Geometry and settings, excluding ephemeral HMONITOR/GDI enumeration names."""
    return sorted([{k: m[k] for k in ('rect', 'work', 'primary', 'dpi', 'current_mode_rect')}
                   for m in rows], key=lambda m: tuple(m['rect']))


def snapshot():
    """Use a physical-pixel thread context and restore it before returning."""
    user.SetThreadDpiAwarenessContext.argtypes = [c.c_void_p]
    user.SetThreadDpiAwarenessContext.restype = c.c_void_p
    before = user.SetThreadDpiAwarenessContext(c.c_void_p(-4))
    if not before:
        raise c.WinError(c.get_last_error())
    callback = c.WINFUNCTYPE(w.BOOL, w.HANDLE, w.HDC, c.POINTER(w.RECT), w.LPARAM)
    user.EnumDisplayMonitors.argtypes = [w.HDC, c.POINTER(w.RECT), callback, w.LPARAM]
    user.GetMonitorInfoW.argtypes = [w.HANDLE, c.POINTER(MonitorInfo)]
    user.EnumDisplaySettingsW.argtypes = [w.LPCWSTR, w.DWORD, c.c_void_p]
    shcore = c.WinDLL('shcore')
    shcore.GetDpiForMonitor.argtypes = [w.HANDLE, c.c_int, c.POINTER(w.UINT), c.POINTER(w.UINT)]
    rows, errors = [], []

    @callback
    def visit(handle, hdc, region, unused):
        # Exceptions cannot escape a ctypes callback.
        try:
            info = MonitorInfo()
            info.size = c.sizeof(info)
            if not user.GetMonitorInfoW(handle, c.byref(info)):
                raise c.WinError(c.get_last_error())
            x, y = w.UINT(), w.UINT()
            if shcore.GetDpiForMonitor(handle, 0, c.byref(x), c.byref(y)) != 0:
                raise RuntimeError('GetDpiForMonitor failed')
            mode = c.create_string_buffer(220)
            struct.pack_into('<H', mode, 68, 220)
            if not user.EnumDisplaySettingsW(info.device, 0xFFFFFFFF, mode):
                raise c.WinError(c.get_last_error())
            mode_rect = list(struct.unpack_from('<ii', mode, 76)) + list(struct.unpack_from('<II', mode, 172))
            if mode_rect != xywh(info.rect):
                raise AssertionError(('DEVMODE and MONITORINFO rectangles differ', info.device, mode_rect, xywh(info.rect)))
            rows.append(dict(id=int(handle), device=info.device, rect=xywh(info.rect),
                             work=xywh(info.work), primary=bool(info.flags & 1), dpi=[x.value, y.value],
                             current_mode_rect=mode_rect))
        except Exception as error:
            errors.append(error)
            return False
        return True
    try:
        ok = user.EnumDisplayMonitors(None, None, visit, 0)
        if errors:
            raise errors[0]
        if not ok:
            raise c.WinError(c.get_last_error())
        return sorted(rows, key=lambda row: row['device'])
    finally:
        user.SetThreadDpiAwarenessContext(before)


def available_modes(device):
    """DEVMODEW, as used by host_display; no ChangeDisplaySettings call."""
    rows = set()
    user.EnumDisplaySettingsW.argtypes = [w.LPCWSTR, w.DWORD, c.c_void_p]
    for index in range(10000):
        mode = c.create_string_buffer(220)
        struct.pack_into('<H', mode, 68, 220)
        if not user.EnumDisplaySettingsW(device, index, mode):
            return [list(row) for row in sorted(rows)]
        rows.add(struct.unpack_from('<III', mode, 172)[0:2] + (struct.unpack_from('<I', mode, 184)[0],))
    raise RuntimeError('EnumDisplaySettingsW exceeded 10000 modes')
