# syntax=docker/dockerfile:1.29@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183
# SPDX-FileCopyrightText: © 2025 VEXXHOST, Inc.
# SPDX-License-Identifier: GPL-3.0-or-later

ARG FROM=ghcr.io/vexxhost/ubuntu-cloud-archive:2026.2@sha256:7cb411eedd115571a976f1d438af8bba51af093b9ac0dc9b881c8da3360232ae

FROM ${FROM} AS qemu-builder
ARG TARGETARCH
ARG QEMU_COMMIT=bb0b78fbc9cb23b9c6dfb53b6075637b75b56794
ARG QEMU_PACKAGE_VERSION=1:10.2.1+ds-1ubuntu3.3+vexxhost1
RUN if [ "${TARGETARCH}" = amd64 ]; then \
        apt-get update && \
        apt-get install --no-install-recommends -y \
            build-essential \
            devscripts \
            equivs \
            git \
            quilt; \
    fi
WORKDIR /src/qemu
RUN if [ "${TARGETARCH}" = amd64 ]; then \
        git init && \
        git remote add origin https://git.launchpad.net/ubuntu/+source/qemu && \
        git fetch --depth=1 origin ${QEMU_COMMIT} && \
        git checkout --detach FETCH_HEAD && \
        mk-build-deps \
            --build-dep \
            --install \
            --remove \
            --tool 'apt-get -y --no-install-recommends' \
            debian/control; \
    fi
COPY patches/qemu /patches/qemu
COPY hack/build-qemu /usr/local/bin/build-qemu
RUN --network=none if [ "${TARGETARCH}" = amd64 ]; then \
        QEMU_PACKAGE_VERSION=${QEMU_PACKAGE_VERSION} build-qemu; \
    else \
        mkdir /out; \
    fi

FROM ${FROM}
ARG TARGETARCH
ARG QEMU_PACKAGE_VERSION=1:10.2.1+ds-1ubuntu3.3+vexxhost1
RUN groupadd -g 42424 nova && \
    useradd -u 42424 -g 42424 -M -d /var/lib/nova -s /usr/sbin/nologin -c "Nova User" nova && \
    mkdir -p /etc/nova /var/log/nova /var/lib/nova /var/cache/nova && \
    chown -Rv nova:nova /etc/nova /var/log/nova /var/lib/nova /var/cache/nova
RUN --mount=type=bind,from=qemu-builder,source=/out,target=/qemu-debs,ro \
    if [ "${TARGETARCH}" = amd64 ]; then \
        QEMU_DEBS=/qemu-debs/*.deb; QEMU_SYSTEM=qemu-system-x86; \
    else \
        QEMU_SYSTEM=qemu-system-arm; \
    fi && \
    apt-get update -qq && \
    apt-get install -qq -y --no-install-recommends \
        apparmor \
        ceph-common \
        cgroup-tools \
        dmidecode \
        ebtables \
        iproute2 \
        ipxe-qemu \
        ipxe-qemu-256k-compat-efi-roms \
        kmod \
        libtpms0 \
        libvirt-clients \
        libvirt-daemon-system \
        mdevctl \
        openssh-client \
        openvswitch-switch \
        ovmf \
        pm-utils \
        qemu-block-extra \
        qemu-efi-aarch64 \
        ${QEMU_SYSTEM} \
        seabios \
        swtpm \
        swtpm-tools \
        ${QEMU_DEBS} && \
    if [ "${TARGETARCH}" = amd64 ]; then \
        test "$(dpkg-query -W -f='${Version}' qemu-block-extra)" = "${QEMU_PACKAGE_VERSION}" && \
        test "$(dpkg-query -W -f='${Version}' qemu-system-common)" = "${QEMU_PACKAGE_VERSION}" && \
        test "$(dpkg-query -W -f='${Version}' qemu-system-x86)" = "${QEMU_PACKAGE_VERSION}" && \
        RBD_PROBE_OUTPUT="$(timeout 5 qemu-system-x86_64 -display none -nodefaults \
            -blockdev '{"driver":"rbd","pool":"__probe__","image":"__probe__","server":[{"host":"127.0.0.1","port":"1"}],"node-name":"rbd-probe"}' 2>&1 || true)" && \
        if printf '%s\n' "${RBD_PROBE_OUTPUT}" | grep -Eq "Unable to load block driver rbd|Unknown driver 'rbd'"; then \
            printf '%s\n' "${RBD_PROBE_OUTPUT}" >&2; \
            exit 1; \
        fi; \
    fi && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
