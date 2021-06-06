#!/bin/bash
#
set -e

echo "Building OpenSSL"

export OPENSSL_VERSION=$1

architecture=""
case $(uname -m) in
    x86_64) architecture="amd64" ;;
    aarch64) architecture="arm64" ;;
esac

linkdir=""
case $architecture in
    amd64) linkdir="x86_64-linux-gnu" ;;
    arm64) linkdir="aarch64-linux-gnu" ;;
esac

opensslarch=""
case $architecture in
    amd64) opensslarch="linux-x86_64" ;;
    arm64) opensslarch="linux-aarch64" ;;
esac

ls /usr/include/linux

mkdir -p /usr/local/musl/include

ln -s /usr/include/linux /usr/local/musl/include/linux
ln -s /usr/include/$linkdir/asm /usr/local/musl/include/asm
ln -s /usr/include/asm-generic /usr/local/musl/include/asm-generic

cd /tmp

short_version="$(echo "$OPENSSL_VERSION" | sed s'/[a-z]$//' )"

curl -fLO "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz"

tar xvzf "openssl-$OPENSSL_VERSION.tar.gz" && cd "openssl-$OPENSSL_VERSION"

env CC=musl-gcc ./Configure no-shared no-zlib no-tests -fPIC --prefix=/usr/local/musl -DOPENSSL_NO_SECURE_MEMORY $opensslarch
env C_INCLUDE_PATH=/usr/local/musl/include/ make -j$(nproc)
make install_sw
rm /usr/local/musl/include/linux /usr/local/musl/include/asm /usr/local/musl/include/asm-generic

rm -r /tmp/*