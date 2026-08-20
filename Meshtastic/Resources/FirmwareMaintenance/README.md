# iOS factory-erase images

These UF2 images are built from `meshtastic/nrf52_factory_erase` commit
`c48244bd65e54a04fac80de36e59eeb3a12289ad` with one behavioral change:
the image does not wait for a USB CDC/DTR host before formatting the internal
filesystem. That wait prevents the published images from running when copied
from iOS or iPadOS.

Rebuild them with:

```sh
scripts/firmware/build-ios-factory-erase.sh
```

The script pins the PlatformIO platform and Arduino framework commit, applies
`nrf52-factory-erase-ios.patch`, builds both supported SoftDevice variants, and
checks the SHA-256 values embedded in the app's maintenance catalog.

| File | SoftDevice | First target | SHA-256 |
| --- | --- | --- | --- |
| `nrf52-factory-erase-s140-6.1.1-ios.uf2` | S140 6.1.1 | `0x26000` | `30abd2d05a5c0aeb737f3018539813a31371f919abc6a5dba5e62cddac1fdbc8` |
| `nrf52-factory-erase-s140-7.3.0-ios.uf2` | S140 7.3.0 | `0x27000` | `919721f1129c9b79edaa631a2eb0e00d0274ba2478af2563233e744613ec4c00` |
