#!/usr/bin/env python3
"""Strip the per-message static accessors from the generated field-metadata registry.

The plugin emits, for every annotated field:

    extension Config.LoRaConfig {
        public static var modemPreset: FieldMetadata { ... }
    }

Across modules that shadows the real settable property. `lora.modemPreset = x`
stops compiling with "static member 'modemPreset' cannot be used on instance",
and our registry has to live in the app target while the protobuf types live in
MeshtasticProtobufs, because String(localized:) is only extracted from a target
that owns a string catalog.

Reported upstream: meshtastic/protobufs#952. If the accessors are nested there,
this step becomes a no-op and should be deleted.

Enum extensions are KEPT - `public var metadata` is an instance member on the
enum and shadows nothing - as is FieldMetadataRegistry itself, which is what the
index actually reads.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()

# A message accessor block is an extension whose body is only `public static var`
# lines. An enum block contains `public var metadata`, so it never matches.
block = re.compile(
    r"^extension [\w.]+ \{\n(?:    public static var \w+: FieldMetadata \{ .*\n)+\}\n\n",
    re.M,
)
out, removed = block.subn("", src)
if removed:
    path.write_text(out)
print(f"  stripped {removed} message accessor blocks (see {Path(__file__).name})")
