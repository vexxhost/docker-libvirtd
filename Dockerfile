# SPDX-FileCopyrightText: © 2025 VEXXHOST, Inc.
# SPDX-License-Identifier: GPL-3.0-or-later

FROM ghcr.io/vexxhost/ubuntu-cloud-archive:main@sha256:a4aed409fddc019d83d0b949a0326fa532b6bdf7c406eb2d672340180aa3860f
RUN groupadd -g 42424 nova && \
    useradd -u 42424 -g 42424 -M -d /var/lib/nova -s /usr/sbin/nologin -c "Nova User" nova && \
    mkdir -p /etc/nova /var/log/nova /var/lib/nova /var/cache/nova && \
    chown -Rv nova:nova /etc/nova /var/log/nova /var/lib/nova /var/cache/nova
RUN apt-get update -qq && \
    apt-get install -qq -y --no-install-recommends \
        ceph-common \
        cgroup-tools \
        dmidecode \
        ebtables \
        iproute2 \
        ipxe-qemu \
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
        swtpm-tools && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
