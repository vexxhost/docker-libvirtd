# SPDX-FileCopyrightText: © 2025 VEXXHOST, Inc.
# SPDX-License-Identifier: GPL-3.0-or-later

FROM ghcr.io/vexxhost/ubuntu-cloud-archive:2023.2@sha256:1cf32e90380f0d992134cddc7d92ee31bab9634635f7e129b1e4ab05bc7a37dd
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
        ipxe-qemu-256k-compat-efi-roms \
        kmod \
        libtpms0 \
        libvirt-clients \
        libvirt-daemon-system \
        openssh-client \
        openvswitch-switch \
        ovmf \
        pm-utils \
        qemu-block-extra \
        qemu-efi \
        qemu-kvm \
        seabios \
        swtpm \
        swtpm-tools && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
