#!/bin/bash

set -ev

source ".travis/config/$ARCH.sh" || true

TAG="$REPOSITORY/$PROJECT-$ARCH"
TAGSPECIFIER="$DISTRIBUTION"
QEMUBUILDPACK="$REPOSITORY/buildpack-amd64:jessie"
QEMUDIRECTORY="mkimage-qemu"
QEMUVERSION="v2.6.0"

mkimageqemu () {
    [ -z "$QEMU_TARGET" ] && return

    rm -rf   "$QEMUDIRECTORY"
    mkdir -p "$QEMUDIRECTORY"

    QEMU_NAME="qemu-${QEMU_TARGET%%-*}"
    QEMU_NAME_STATIC="$QEMU_NAME-static"

    cat <<-EOF > "$QEMUDIRECTORY/Dockerfile.qemu.static"
		FROM $QEMUBUILDPACK
		RUN apt-get update && apt-get -y install git libglib2.0-dev libfdt-dev libpixman-1-dev zlib1g-dev
		RUN git clone --depth 1 --branch "$QEMUVERSION" https://github.com/qemu/qemu.git /usr/src/qemu
		WORKDIR /usr/src/qemu
		RUN mkdir -p build
		WORKDIR      build
		RUN ../configure --static --target-list="$QEMU_TARGET"
EOF

    docker build -f   "$QEMUDIRECTORY/Dockerfile.qemu.static" -t qemu:static "$QEMUDIRECTORY"
    docker rm         "$QEMU_NAME" || true
    docker run --name "$QEMU_NAME" qemu:static make -j4
    docker cp         "$QEMU_NAME:/usr/src/qemu/build/$QEMU_TARGET/$QEMU_NAME" "/usr/bin/$QEMU_NAME_STATIC"

    strip -s "/usr/bin/$QEMU_NAME_STATIC"
}

mkdir -p mkimage
curl "https://raw.githubusercontent.com/docker/docker/master/contrib/mkimage.sh" >mkimage.sh
curl "https://raw.githubusercontent.com/docker/docker/master/contrib/mkimage/debootstrap" >mkimage/debootstrap
curl "https://anonscm.debian.org/git/pkg-qemu/qemu.git/plain/debian/qemu-debootstrap?h=debian-$DISTRIBUTION" >/usr/sbin/qemu-debootstrap
chmod -R u+x mkimage mkimage.sh /usr/sbin/qemu-debootstrap

patch -p0 --no-backup-if-mismatch < .patch/mkimage/rootfs.patch
patch -p0 --no-backup-if-mismatch < .patch/mkimage/docker.patch
patch -p0 --no-backup-if-mismatch < .patch/debootstrap/aptitude.patch
patch -p0 --no-backup-if-mismatch < .patch/debootstrap/source.patch

  mkimageqemu
./mkimage.sh -t "$PROJECT:$DISTRIBUTION" debootstrap --arch="$ARCH" --components=main,universe "$CONFIGURATION" "$DISTRIBUTION" "$MIRROR"

docker tag "$PROJECT:$DISTRIBUTION" "$TAG:$TAGSPECIFIER"
docker run --rm                     "$TAG:$TAGSPECIFIER" cat /etc/debian_version