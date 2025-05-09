#!/usr/bin/env bash

qemu-system-x86_64 \
    -kernel zig-out/bin/kernel.elf
