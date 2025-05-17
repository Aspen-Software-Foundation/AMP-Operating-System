#!/usr/bin/env bash
set -eu pipefail

mkdir -p iso_root/boot/limine
mkdir -p iso_root/EFI/BOOT
cp assets/limine.conf iso_root/boot/limine/
cp limine/limine-bios.sys limine/limine-*-cd.bin iso_root/boot/limine/
cp limine/BOOTIA32.EFI limine/BOOTX64.EFI iso_root/EFI/BOOT/

zig build
cp zig-out/bin/kernel iso_root/boot/
xorriso -as mkisofs -R -r -J -b boot/limine/limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table -hfsplus -apm-block-size 2048 --efi-boot boot/limine/limine-uefi-cd.bin -efi-boot-part --efi-boot-image --protective-msdos-label iso_root -o image.iso &> /dev/null
limine bios-install image.iso &> /dev/null
qemu-system-x86_64 -cdrom image.iso # <--- For some reason, this line doesn't work when run from the script, but works when run manually -Yazin Tantawi
