#!/usr/bin/env bash
set -eu pipefail

zig build
cp zig-out/bin/kernel iso_root/boot/
xorriso -as mkisofs -R -r -J -b boot/limine/limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table -hfsplus -apm-block-size 2048 --efi-boot boot/limine/limine-uefi-cd.bin -efi-boot-part --efi-boot-image --protective-msdos-label iso_root -o image.iso
limine bios-install image.iso
qemu-system-x86_64 -boot d -m 2G -cdrom image.iso
