#
#  sky.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 10/30/26.
#
#  Renders an HDRI alone as a panorama, for the sky an environment with a cutout image (see
#  render_room's `cutout`) shows behind its glass. Run with build.sh, not by hand:
#
#    Blender -b -P sky.py -- --hdri kiara_8_sunset_8k.hdr --rotation 3 --strength 1 --out out/x.png --width 4096
#
#  The same rotation and strength as the room's render keep the sun where the room's light says it is.

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from room_base import arguments, build_camera, build_world, configure_render  # noqa: E402

options = arguments()
bpy.ops.wm.read_factory_settings(use_empty=True)
build_world(options["hdri"], float(options.get("rotation", 0)), float(options.get("strength", 1)))
build_camera()
configure_render(options)
# Nothing to trace but the background: a few samples are plenty.
bpy.context.scene.cycles.samples = min(options["samples"], 16)
if os.path.exists(options["out"]):
    os.remove(options["out"])
if bpy.ops.render.render(write_still=True) != {"FINISHED"} or not os.path.exists(options["out"]):
    raise SystemExit("render failed: " + options["out"])
print("rendered", options["out"])
