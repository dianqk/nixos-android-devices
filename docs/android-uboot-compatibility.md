# Android and U-Boot compatibility on Asphalt, Sheng and Aurora

[中文](android-uboot-compatibility.zh.md)

The supported installation keeps Android on A, U-Boot on B, and an independent
NixOS recovery. This repository does not provide a combined Android/U-Boot boot
image or support booting Android directly through U-Boot on these boards.
Follow the [Asphalt](asphalt/first-install.md), [Sheng](sheng/first-install.md)
or [Aurora](aurora/README.md) installation guide.

## Installed boot path

OEM boot firmware → `boot_b` U-Boot → `linux-boot` FAT ESP → systemd-boot →
the selected NixOS kernel/initrd → ext4 `linux` root.

The ESP and root are separate outer-GPT partitions in the original userdata
allocation, without A/B suffixes. U-Boot loads EFI; Linux mounts the root.
The OEM firmware selects the Android slot before U-Boot starts. Preserve
Android A and super when preparing the Linux layout.

Independent recovery contains its own kernel, DTB and initrd. It does not depend
on the installed system's kernel or ESP; retain it when updating U-Boot or NixOS.

## Android boot compatibility

U-Boot's upstream [Android image support](https://docs.u-boot-project.org/en/v2026.10/android/boot-image.html)
is not a board compatibility guarantee. An Android boot path still needs matching
DT/DTBO, ramdisks, bootconfig and vendor modules, including `vendor_boot` and,
where applicable, `init_boot`; see the [Android boot layout](https://source.android.com/docs/core/architecture/partitions/generic-boot).
Compiling an Android kernel from source does not supply these inputs or establish
an Android/U-Boot integration. Android and NixOS can use separate kernels.

A bootable Android A slot does not establish a usable Android B slot. Merely
changing `slot_suffix` cannot provide the missing per-slot images, logical
partitions, AVB metadata or firmware. Full Android A/B operation also requires
correct boot success, retry, fallback and OTA handling; see the
[AOSP A/B requirements](https://source.android.com/docs/core/ota/ab/ab_implement).
The installed NixOS generation/rollback mechanism is separate from Android A/B.
