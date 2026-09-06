# SPDX-FileCopyrightText: © 2025 VEXXHOST, Inc.
# SPDX-License-Identifier: GPL-3.0-or-later

FROM ghcr.io/vexxhost/ubuntu-cloud-archive:2023.1@sha256:48e8b85d4d0fa25958b105e88540955d44831316512458a87a29df76550cdf9f
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
