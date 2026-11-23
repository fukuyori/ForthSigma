#!/usr/bin/env python3
"""Read Mutter monitor/scaling inventory for #1336; never apply a configuration.

Optionally verify a secondary scaling candidate with method 0 (verify only).
Requires PyGObject and a GNOME/Mutter session. Physical hotplug is not tested.
"""
import argparse
import json
import os
import sys

if sys.platform != 'linux':
    raise SystemExit('Linux is required')
try:
    import gi
    from gi.repository import Gio, GLib
except ImportError:
    print(json.dumps({'skipped': 'PyGObject is required'}))
    raise SystemExit(77)

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--verify-secondary-scale', type=float)
args = parser.parse_args()
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)


def call(method, params=None):
    return bus.call_sync('org.gnome.Mutter.DisplayConfig',
                         '/org/gnome/Mutter/DisplayConfig',
                         'org.gnome.Mutter.DisplayConfig', method, params, None,
                         Gio.DBusCallFlags.NONE, 5000, None).unpack()


serial, physical, logical, properties = call('GetCurrentState')
by_connector = {monitor[0][0]: monitor for monitor in physical}
rows = []
for spec, modes, props in physical:
    current = [mode for mode in modes if mode[6].get('is-current')]
    rows.append(dict(connector=spec[0], current_modes=[
        dict(id=m[0], width=m[1], height=m[2], hz=m[3], preferred_scale=m[4], supported_scales=m[5])
        for m in current]))
result = dict(task=1336, acceptance=False, physical_hotplug_tested=False,
              configuration_applied=False, session_type=os.environ.get('XDG_SESSION_TYPE'),
              global_scale_required=properties.get('global-scale-required', False),
              layout_mode=properties.get('layout-mode', 1),
              monitors=rows, logical=[dict(x=m[0], y=m[1], scale=m[2], transform=m[3],
                                          primary=m[4], connectors=[s[0] for s in m[5]]) for m in logical])
if args.verify_secondary_scale is not None:
    assert not properties.get('global-scale-required', False), 'independent monitor scales unavailable'
    # Limit the proposal to a known adjacent two-monitor layout; do not guess
    # how to preserve arbitrary mirrors, rotation, leases or color settings.
    assert len(logical) == 2 and properties.get('layout-mode', 1) == 1, 'two logical monitors in logical layout required'
    assert all(len(m[5]) == 1 and m[3] == 0 and m[1] == 0 for m in logical), 'unrotated horizontal independent monitors required'
    primary = next(m for m in logical if m[4])
    secondary = next(m for m in logical if not m[4])
    candidate = []
    dimensions = {}
    for m in logical:
        connector = m[5][0][0]
        _, modes, props = by_connector[connector]
        mode, = [mode for mode in modes if mode[6].get('is-current')]
        scale = m[2] if m[4] else args.verify_secondary_scale
        assert scale in mode[5], ('unsupported scale', connector, scale)
        assert not props.get('is-underscanning') and props.get('color-mode', 0) == 0, 'nondefault monitor properties require explicit preservation'
        dimensions[connector] = int(round(mode[1] / scale))
        candidate.append([0, 0, scale, m[3], m[4], [(connector, mode[0], {})]])
    # Preserve the left-to-right ordering, keeping the logical layout adjacent.
    order = sorted(range(2), key=lambda i: logical[i][0])
    x = 0
    for i in order:
        candidate[i][0] = x
        x += dimensions[candidate[i][5][0][0]]
    config_properties = {}
    if properties.get('supports-changing-layout-mode'):
        config_properties['layout-mode'] = GLib.Variant('u', 1)
    # This tool deliberately has no temporary/persistent apply option.
    call('ApplyMonitorsConfig', GLib.Variant('(uua(iiduba(ssa{sv}))a{sv})',
                                           (serial, 0, candidate, config_properties)))
    result['verified_secondary_scale'] = args.verify_secondary_scale
    result['candidate'] = [dict(x=m[0], y=m[1], scale=m[2], primary=m[4], connector=m[5][0][0]) for m in candidate]
print(json.dumps(result, indent=2))
