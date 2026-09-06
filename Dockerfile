# syntax=docker/dockerfile:1.26@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# SPDX-FileCopyrightText: © 2025 VEXXHOST, Inc.
# SPDX-License-Identifier: GPL-3.0-or-later

ARG FROM=ghcr.io/vexxhost/ubuntu-cloud-archive:2025.2@sha256:351957d5ec9c01150ecbfa2d311957fe2c66a630a3b9efdb6b6cd83cb518a158

FROM ${FROM} AS qemu-builder
ARG TARGETARCH
ARG QEMU_COMMIT=c509d34e5d97b1949b8daafbb53afdd036c2195d
ARG QEMU_PACKAGE_VERSION=1:8.2.2+ds-0ubuntu1.18+vexxhost2
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
ARG QEMU_PACKAGE_VERSION=1:8.2.2+ds-0ubuntu1.18+vexxhost2
RUN groupadd -g 42424 nova && \
    useradd -u 42424 -g 42424 -M -d /var/lib/nova -s /usr/sbin/nologin -c "Nova User" nova && \
    mkdir -p /etc/nova /var/log/nova /var/lib/nova /var/cache/nova && \
    chown -Rv nova:nova /etc/nova /var/log/nova /var/lib/nova /var/cache/nova
RUN --mount=type=bind,from=qemu-builder,source=/out,target=/qemu-debs,ro \
    if [ "${TARGETARCH}" = amd64 ]; then QEMU_DEBS=/qemu-debs/*.deb; fi && \
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
        qemu-kvm \
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
