#!/usr/bin/env python3
"""Run real patched DRM/panel callbacks with fault-injectable hardware fakes.

Pass a kernel tree after applying the Unicorn patch queue. This tests ownership,
callback ordering and lock recursion, not hardware timings or physical display.
"""

import argparse
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile


def block(source, start):
    """Find the closing brace, ignoring braces in strings and comments."""
    opening = source.index("{", start)
    depth = 0
    tokens = r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|/\*.*?\*/|//[^\n]*|[{}]'
    for token in re.finditer(tokens, source[opening:], re.S):
        if token.group() == "{":
            depth += 1
        elif token.group() == "}":
            depth -= 1
            if depth == 0:
                return source[start:opening + token.end()] + "\n"
    raise ValueError("unterminated C block")


def function(source, name):
    match = re.search(
        r"(?m)^(?:(?:static|inline)\s+)*(?:void|bool|int|long)\s+"
        + re.escape(name) + r"\([^;]*?\)\s*\{", source, re.S
    )
    if not match:
        raise ValueError(f"missing source function: {name}")
    return block(source, match.start())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    args = parser.parse_args()
    drm = args.source.resolve() / "drivers/gpu/drm"
    panel = (drm / "panel/panel-xiaomi-l2s-380c0a.c").read_text()
    bridge = (drm / "bridge/panel.c").read_text()
    core = (drm / "drm_atomic_helper.c").read_text()
    duplicate = (drm / "drm_atomic_state_helper.c").read_text()
    wrappers = (drm / "drm_panel.c").read_text()
    dsi = (drm / "msm/dsi/dsi_manager.c").read_text()
    fixture = Path(__file__).with_suffix(".c").read_text()
    panel_functions = [
        "l2s_panel_get_current_mode", "l2s_runtime_send", "l2s_idle_supported",
        "l2s_idle_enter", "l2s_panel_init", "l2s_panel_power_off",
        "l2s_panel_prepare_locked", "l2s_panel_prepare", "l2s_panel_post_on",
        "l2s_panel_enable_locked", "l2s_panel_enable", "l2s_panel_disable_locked",
        "l2s_panel_disable", "l2s_panel_unprepare_locked", "l2s_panel_unprepare",
        "l2s_write_brightness_locked", "l2s_idle_exit", "l2s_backlight_wake",
        "l2s_backlight_work", "l2s_stop_backlight_work",
        "l2s_panel_get_modes",
        "l2s_panel_bl_update_status",
    ]
    replacements = {
        "PANEL_STRUCT": block(panel, panel.index("struct l2s_panel {")) + ";\n",
        "PANEL_MODES": block(panel, panel.index("static const struct drm_display_mode l2s_panel_modes[]")) + ";\n",
        "PANEL_FUNCTIONS": "\n".join(function(panel, name) for name in panel_functions),
        "DUPLICATE": function(duplicate, "__drm_atomic_helper_crtc_duplicate_state"),
        "CORE_FUNCTIONS": "\n".join(
            function(wrappers, "drm_panel_" + name)
            for name in ["prepare", "enable", "disable", "unprepare"]
        ) + "\n".join(function(bridge, "panel_bridge_atomic_" + name) for name in ["pre_enable", "enable", "disable", "post_disable"])
        + function(core, "crtc_needs_disable"),
        "DSI_FUNCTIONS": "\n".join(function(dsi, name) for name in [
            "dsi_mgr_phy_disable", "dsi_mgr_bridge_pre_enable", "dsi_mgr_bridge_post_disable",
        ]),
    }
    for name, value in replacements.items():
        marker = "/* @" + name + "@ */"
        if fixture.count(marker) != 1:
            raise ValueError(f"invalid fixture marker: {marker}")
        fixture = fixture.replace(marker, value)
    with tempfile.TemporaryDirectory(prefix="unicorn-display-") as directory:
        source = Path(directory) / "lifecycle.c"
        executable = Path(directory) / "lifecycle"
        source.write_text(fixture)
        subprocess.run(shlex.split(os.environ.get("CC", "cc")) + [
            "-std=gnu11", "-O2", "-g", "-Wall", "-Wextra", "-Werror",
            "-Wno-unused-parameter", "-Wno-unused-function", "-Wno-sign-compare",
            "-I", str(drm / "panel"), str(source), "-o", str(executable),
        ], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
