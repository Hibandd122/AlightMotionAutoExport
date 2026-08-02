# 120 FPS project option

`FPS120.m` adds a separate `120 FPS` button when the app presents `CreateVC`.

The button is attached below the existing `valueFrameRateButton`. When tapped it:

1. marks the controller as having selected 120 FPS;
2. attempts to write `120` through the FPS-related Objective-C/KVC names visible in the binary;
3. re-applies the value immediately before the original `onTapCreate:` handler runs.

The IPA does not contain the original Swift source, so the exact private setter used by the app could not be proven statically. A successful Theos build and runtime test must verify that a newly created project reports 120 FPS and that an exported video has a 120 FPS nominal frame rate.

Build from a macOS/Theos environment with:

```sh
make package FINALPACKAGE=1
```

This workspace does not have Theos configured, so the package cannot be built or runtime-tested here.
