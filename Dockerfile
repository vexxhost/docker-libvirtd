# syntax=docker/dockerfile:1.7@sha256:a57df69d0ea827fb7266491f2813635de6f17269be881f696fbfdf2d83dda33e
# SPDX-FileCopyrightText: © 2025 VEXXHOST, Inc.
# SPDX-License-Identifier: GPL-3.0-or-later

ARG FROM=ghcr.io/vexxhost/ubuntu-cloud-archive:main@sha256:8ecef42d4bdd95bafa380b459b895cb50cb361dc854dda1c74484ae8f1e6d395

FROM ${FROM} AS qemu-builder
ARG TARGETARCH
ARG QEMU_COMMIT=c509d34e5d97b1949b8daafbb53afdd036c2195d
ARG QEMU_PACKAGE_VERSION=1:8.2.2+ds-0ubuntu1.18+vexxhost1
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
ARG QEMU_PACKAGE_VERSION=1:8.2.2+ds-0ubuntu1.18+vexxhost1
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
        test "$(dpkg-query -W -f='${Version}' qemu-system-x86)" = "${QEMU_PACKAGE_VERSION}"; \
    fi && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
