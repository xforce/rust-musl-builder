#!/bin/bash

case $(uname -m) in
    x86_64)
cat >/opt/rust/cargo/config <<EOF
[build]
# Target musl-libc by default when running Cargo.
target = "x86_64-unknown-linux-musl"

[target.armv7-unknown-linux-musleabihf]
linker = "arm-linux-gnueabihf-gcc"
EOF
    ;;
    aarch64)
cat >/opt/rust/cargo/config <<EOF
[build]
# Target musl-libc by default when running Cargo.
target = "aarch64-unknown-linux-musl"

[target.armv7-unknown-linux-musleabihf]
linker = "arm-linux-gnueabihf-gcc"
EOF
    ;;
esac
