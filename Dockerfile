# Use Ubuntu 20.04 LTS as our base image.
FROM ubuntu:20.04

# The Rust toolchain to use when building our image.  Set by `hooks/build`.
ARG TOOLCHAIN=stable

# The OpenSSL version to use. Here is the place to check for new releases:
#
# - https://www.openssl.org/source/
#
# ALSO UPDATE hooks/build!
ARG OPENSSL_VERSION=1.1.1i

# Versions for other dependencies. Here are the places to check for new
# releases:
#
# - http://zlib.net/
# - https://ftp.postgresql.org/pub/source/
#
# We're stuck on PostgreSQL 11 until we figure out
# https://github.com/emk/rust-musl-builder/issues.
ARG ZLIB_VERSION=1.2.11
ARG POSTGRESQL_VERSION=11.11

# Make sure we have basic dev tools for building C libraries.  Our goal here is
# to support the musl-libc builds and Cargo builds needed for a large selection
# of the most popular crates.
#
# We also set up a `rust` user by default. This user has sudo privileges if you
# need to install any more software.
#
RUN apt-get update -y && \
    export DEBIAN_FRONTEND=noninteractive && \
    apt-get install -yq \
    build-essential \
    cmake \
    curl \
    file \
    git \
    graphviz \
    musl-dev \
    musl-tools \
    libpq-dev \
    libsqlite-dev \
    libssl-dev \
    linux-libc-dev \
    pkgconf \
    sudo \
    xutils-dev \
    && \
    # apt-get clean && rm -rf /var/lib/apt/lists/* && \
    useradd rust --user-group --create-home --shell /bin/bash --groups sudo

# Static linking for C++ code
RUN ln -s "/usr/bin/g++" "/usr/bin/musl-g++"

# Build a static library version of OpenSSL using musl-libc.  This is needed by
# the popular Rust `hyper` crate.
#
# We point /usr/local/musl/include/linux at some Linux kernel headers (not
# necessarily the right ones) in an effort to compile OpenSSL 1.1's "engine"
# component. It's possible that this will cause bizarre and terrible things to
# happen. There may be "sanitized" header
ADD build_openssl.sh .
RUN ./build_openssl.sh $OPENSSL_VERSION && rm ./build_openssl.sh

RUN echo "Building zlib" && \
    cd /tmp && \
    curl -fLO "http://zlib.net/zlib-$ZLIB_VERSION.tar.gz" && \
    tar xzf "zlib-$ZLIB_VERSION.tar.gz" && cd "zlib-$ZLIB_VERSION" && \
    CC=musl-gcc ./configure --static --prefix=/usr/local/musl && \
    make -j$(nproc) && make install && \
    rm -r /tmp/*

RUN echo "Building libpq" && \
    cd /tmp && \
    curl -fLO "https://ftp.postgresql.org/pub/source/v$POSTGRESQL_VERSION/postgresql-$POSTGRESQL_VERSION.tar.gz" && \
    tar xzf "postgresql-$POSTGRESQL_VERSION.tar.gz" && cd "postgresql-$POSTGRESQL_VERSION" && \
    CC=musl-gcc CPPFLAGS=-I/usr/local/musl/include LDFLAGS=-L/usr/local/musl/lib ./configure --with-openssl --without-readline --prefix=/usr/local/musl && \
    cd src/interfaces/libpq && make -j$(nproc) all-static-lib && make install-lib-static && \
    cd ../../bin/pg_config && make -j$(nproc) && make install && \
    rm -r /tmp/*

# (Please feel free to submit pull requests for musl-libc builds of other C
# libraries needed by the most popular and common Rust crates, to avoid
# everybody needing to build them manually.)

# Install a `git credentials` helper for using GH_USER and GH_TOKEN to access
# private repositories if desired. We make sure this is configured for root,
# here, and for the `rust` user below.
ADD git-credential-ghtoken /usr/local/bin/ghtoken
RUN git config --global credential.https://github.com.helper ghtoken

# Set up our path with all our binary directories, including those for the
# musl-gcc toolchain and for our Rust toolchain.
#
# We use the instructions at https://github.com/rust-lang/rustup/issues/2383
# to install the rustup toolchain as root.
ENV RUSTUP_HOME=/opt/rust/rustup \
    PATH=/home/rust/.cargo/bin:/opt/rust/cargo/bin:/usr/local/musl/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Install our Rust toolchain and the `musl` target.  We patch the
# command-line we pass to the installer so that it won't attempt to
# interact with the user or fool around with TTYs.  We also set the default
# `--target` to musl so that our users don't need to keep overriding it
# manually.
RUN curl https://sh.rustup.rs -sSf | \
    env CARGO_HOME=/opt/rust/cargo \
    sh -s -- -y --default-toolchain $TOOLCHAIN --profile minimal --no-modify-path && \
    env CARGO_HOME=/opt/rust/cargo \
    rustup component add rustfmt && \
    env CARGO_HOME=/opt/rust/cargo \
    rustup component add clippy && \
    env CARGO_HOME=/opt/rust/cargo \
    rustup target add x86_64-unknown-linux-musl && \
    env CARGO_HOME=/opt/rust/cargo \
    rustup target add aarch64-unknown-linux-musl
ADD generate_cargo_config.sh .
RUN ./generate_cargo_config.sh && rm ./generate_cargo_config.sh

# Set up our environment variables so that we cross-compile using musl-libc by
# default.
ENV X86_64_UNKNOWN_LINUX_MUSL_OPENSSL_DIR=/usr/local/musl/ \
    X86_64_UNKNOWN_LINUX_MUSL_OPENSSL_STATIC=1 \
    AARCH64_UNKNOWN_LINUX_MUSL_OPENSSL_DIR=/usr/local/musl/ \
    AARCH64_UNKNOWN_LINUX_MUSL_OPENSSL_STATIC=1 \
    PQ_LIB_STATIC_X86_64_UNKNOWN_LINUX_MUSL=1 \
    PG_CONFIG_X86_64_UNKNOWN_LINUX_GNU=/usr/bin/pg_config \
    PQ_LIB_STATIC_AARCH64_UNKNOWN_LINUX_MUSL=1 \
    PG_CONFIG_AARCH64_UNKNOWN_LINUX_GNU=/usr/bin/pg_config \
    PKG_CONFIG_ALLOW_CROSS=true \
    PKG_CONFIG_ALL_STATIC=true \
    LIBZ_SYS_STATIC=1 \
    TARGET=musl

# Install some useful Rust tools from source. This will use the static linking
# toolchain, but that should be OK.
#
RUN env CARGO_HOME=/opt/rust/cargo cargo install -f cargo-chef && \
    rm -rf /opt/rust/cargo/registry/

# Allow sudo without a password.
ADD sudoers /etc/sudoers.d/nopasswd

# Run all further code as user `rust`, create our working directories, install
# our config file, and set up our credential helper.
#
# You should be able to switch back to `USER root` from another `Dockerfile`
# using this image if you need to do so.
USER rust
RUN mkdir -p /home/rust/libs /home/rust/src /home/rust/.cargo && \
    ln -s /opt/rust/cargo/config /home/rust/.cargo/config && \
    git config --global credential.https://github.com.helper ghtoken

# Expect our source code to live in /home/rust/src.  We'll run the build as
# user `rust`, which will be uid 1000, gid 1000 outside the container.
WORKDIR /app
