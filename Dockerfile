# SPDX-FileCopyrightText: © 2025 VEXXHOST, Inc.
# SPDX-License-Identifier: GPL-3.0-or-later

FROM ghcr.io/vexxhost/ubuntu-cloud-archive:2023.1@sha256:2d2c3b5921bc65c3c0fc24322a2605c2cf66efbdb48fb158834889128f832551
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
