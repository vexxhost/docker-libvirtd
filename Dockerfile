# SPDX-FileCopyrightText: © 2025 VEXXHOST, Inc.
# SPDX-License-Identifier: GPL-3.0-or-later

FROM ghcr.io/vexxhost/ubuntu-cloud-archive:2025.2@sha256:71d38fd9f95e0d228fd030e6544212b71ab9f1811005a8807a79668b4bd8e2f8
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
