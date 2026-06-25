# iOS build (FP-12)

Cross-compiles the C++ core (`../../../src`) and its native deps (OpenSSL 3,
Poco, jsoncpp) for iOS, to be linked into the Flutter Runner. Requires a **macOS
host with Xcode** (the CI `ios` job runs on `macos-14`).

## What the CI `ios` job verifies

1. `build-deps-ios.sh iphoneos arm64` — cross-builds the static deps into
   `.deps-prefix/iphoneos`.
2. `cmake -DCMAKE_SYSTEM_NAME=iOS …` builds the core as a **static** lib
   (`libTogglDesktopLibrary.a`) for `iphoneos/arm64`, proving the core + the FFI
   bridge compile for iOS (the core uses a no-op window stub and drops AppKit on
   iOS — see `../CMakeLists.txt`).
3. `flutter build ios --no-codesign` — proves the Flutter iOS app compiles.

## Remaining step (do on a Mac)

Linking the static core into the Runner so `DynamicLibrary.process()` finds the
`toggl_*` / `rt_*` symbols at runtime. The clean way is a small CocoaPod that
vends the prebuilt static lib + deps, referenced from `ios/Podfile`:

```ruby
# ios/Podfile
pod 'RedtickCore', :path => '../native/ios'   # podspec with vendored_libraries
```

The podspec lists `vendored_libraries` (`libTogglDesktopLibrary.a` + the Poco/
OpenSSL/jsoncpp `.a`s) and the required system frameworks (`Foundation`,
`CFNetwork`, `Security`, `libz`, `libc++`). Alternatively add them directly to the
Runner target in Xcode. This wasn't authored blind because it requires the actual
Xcode project; it's the one piece best done on the Mac.

Simulator builds: run `./build-deps-ios.sh iphonesimulator arm64 x86_64` and
build with `-DCMAKE_OSX_SYSROOT=iphonesimulator`.

## Signing / store

`flutter build ipa` with an Apple Developer account + provisioning profile (FP-63),
configured in Xcode / CI secrets.
