#!/usr/bin/env python3
"""Inspect the built firmware and Android v4 envelope; no device access."""
import pathlib
import struct
import subprocess
import sys
import zlib

firmware, image = map(pathlib.Path, sys.argv[1:])
blob = image.read_bytes()
u32 = lambda offset: struct.unpack_from('<I', blob, offset)[0]
assert blob[:8] == b'ANDROID!'
assert u32(40) == 4 and u32(20) == 1584
# No ramdisk and no command line, as in iLtanaka's packing.
assert u32(12) == 0
assert not any(blob[44:44 + 1536])
# os_version 16.0.0, patch level 2026-08 (Android boot image encoding).
assert u32(16) == (16 << 25) | ((2026 - 2000) << 4) | 8
assert len(blob) <= 192 * 1024 * 1024  # boot_b
firmware_image = (firmware / 'u-boot.bin').read_bytes()
dtb = (firmware / 'u-boot.dtb').read_bytes()
payload = blob[4096:4096 + u32(8)]
# ABL takes the DTB appended after the gzip stream.
stream = zlib.decompressobj(31)
assert stream.decompress(payload) == firmware_image and stream.eof
assert stream.unused_data == dtb
kernel = firmware_image
assert kernel[56:60] == b'ARM\x64'
text_offset, memory_size = struct.unpack_from('<QQ', kernel, 8)
assert text_offset == 0, f'Unexpected ARM64 Image text_offset: {text_offset:#x}'
# The control DT travels inside u-boot.bin as well.
assert kernel.endswith(dtb)
config = (firmware / '.config').read_text().splitlines()
for option in ['CLK_QCOM_SM8450', 'PINCTRL_QCOM_SM8450', 'PHY_QCOM_QMP_UFS',
               'PHY_QCOM_SNPS_EUSB2', 'USB_FUNCTION_ACM', 'QCOM_PREFER_PREVBL_MEMORY',
               'DM_REGULATOR_QCOM_RPMH', 'VIDEO_SIMPLE', 'BUTTON_QCOM_PMIC',
               'EFI_LOADER', 'CMD_BOOTEFI', 'FS_FAT_HANDLE_SECTOR_SIZE_MISMATCH']:
    assert f'CONFIG_{option}=y' in config, option
# Qualcomm A/B profile: B is confirmed after the linux-boot ESP entry loads.
# Every enabled LUN has a GPT, so no zero-metadata exceptions; no charger.
for option in ['EFI_MOBILE_BOOT_ACTION', 'EFI_MOBILE_BOOT_ACTION_QCOM_AB',
               'EFI_MOBILE_QCOM_AB_CONFIRM', 'UFS_QCOM', 'SYSRESET_PSCI']:
    assert f'CONFIG_{option}=y' in config, option
for line in ['CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_ESP="linux-boot"',
             'CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_PATH="/EFI/BOOT/BOOTAA64.EFI"',
             'CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_CHARGER_PATH=""',
             'CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_NON_GPT_LUN_MASK=0',
             'CONFIG_EFI_MOBILE_QCOM_AB_ANDROID_NON_GPT_LUN_MASK=0']:
    assert line in config, line
# No MMC flashing or capsule updates.
for option in ['FASTBOOT_FLASH', 'EFI_RUNTIME_UPDATE_CAPSULE',
               'EFI_CAPSULE_ON_DISK', 'EFI_CAPSULE_FIRMWARE_RAW']:
    assert f'CONFIG_{option}=y' not in config, option


def prop(node, name, kind='s'):
    return subprocess.check_output(['fdtget', '-t', kind, str(firmware / 'u-boot.dtb'),
                                    node, name], text=True).strip()


assert prop('/', 'compatible') == 'xiaomi,marble qcom,sm7475 qcom,sm8475 qcom,sm8450'
assert prop('/', 'qcom,msm-id', 'x') == '24f 10000'
assert prop('/', 'qcom,board-id', 'x') == '10008 0'
assert prop('/chosen/framebuffer@b8000000', 'reg', 'x') == '0 b8000000 0 2b00000'
assert prop('/chosen/framebuffer@b8000000', 'width', 'u') == '1080'
assert prop('/chosen/framebuffer@b8000000', 'height', 'u') == '2400'
assert prop('/reserved-memory/splash_region@b8000000', 'reg', 'x') == '0 b8000000 0 2b00000'
assert prop('/soc@0/usb@a600000', 'dr_mode') == 'peripheral'
# The A/B backend's runtime contract: exactly one qcom,ufshc and the PMK8350
# SDAM reboot-mode cell (0x7148, bits 1..7; recovery 1, bootloader 2).
assert 'qcom,ufshc' in prop('/soc@0/ufshc@1d84000', 'compatible').split()
assert prop('/reboot-mode', 'compatible') == 'nvmem-reboot-mode'
assert prop('/reboot-mode', 'mode-recovery', 'u') == '1'
assert prop('/reboot-mode', 'mode-bootloader', 'u') == '2'
cell = '/soc@0/spmi@c400000/pmic@0/nvram@7100/reboot-reason@48'
assert prop(cell, 'reg', 'x') == '48 1' and prop(cell, 'bits', 'x') == '1 7'
assert prop(cell, 'phandle', 'x') == prop('/reboot-mode', 'nvmem-cells', 'x')
assert prop('/soc@0/spmi@c400000/pmic@0/nvram@7100', 'compatible') == 'qcom,spmi-sdam'
assert prop('/soc@0/spmi@c400000/pmic@0', 'compatible').split()[-1] == 'qcom,spmi-pmic'
# ACM starts on every boot before storage is scanned.
assert b'preboot=run serial_gadget; scsi scan' in kernel
assert b'stdout vidconsole,serial,usbacm' in kernel
assert b'linux-boot' in kernel and b'/EFI/BOOT/BOOTAA64.EFI' in kernel
# RAM recovery: a "ram-recovery" FIT ramdisk after vendor_boot_b's ramdisk.
assert b'preboot=run serial_gadget; scsi scan; run boot_payload' in kernel
for marker in [b'android-devices,payload', b'vendor_boot_b', b'prevbl_initrd_start_addr',
               b'itest ${payload_size} -le 0x7000000', b'setenv bootcmd run menucmd']:
    assert marker in kernel, marker
assert 'CONFIG_SAVE_PREV_BL_INITRAMFS_START_ADDR=y' in config
assert 'CONFIG_FASTBOOT_BUF_SIZE=0x7000000' in config
# Panel variant: ABL's msm_drm.dsi_display0 selects the panel compatible and
# vddd in the OS DT through ft_board_setup() (bootm and EFI DT fixup).
for option in ['OF_BOARD_SETUP', 'EFI_DT_FIXUP', 'SAVE_PREV_BL_FDT_ADDR']:
    assert f'CONFIG_{option}=y' in config, option
variants = '/dsi-panel-variants'
assert prop(variants, 'compatible') == 'android-devices,dsi-panel-variants'
assert prop(variants, 'bootarg') == 'msm_drm.dsi_display0'
for node, abl, compatible, microvolt in [
        ('variant-36-02-0a', 'qcom,mdss_dsi_m16t_36_02_0a_dsc_vid', 'xiaomi,marble-m16t-36-02-0a', '1200000'),
        ('variant-36-0d-0b', 'qcom,mdss_dsi_m16t_36_0d_0b_dsc_vid', 'xiaomi,marble-m16t-36-0d-0b', '1256000')]:
    assert prop(f'{variants}/{node}', 'abl-panel') == abl
    assert prop(f'{variants}/{node}', 'panel-compatible') == compatible
    assert prop(f'{variants}/{node}', 'supply-name') == 'vddd'
    assert prop(f'{variants}/{node}', 'supply-microvolt', 'u') == microvolt
assert b'Panel: %s -> %s' in kernel
# A 3 s autoboot countdown stops at the shell on any key; an idle shell
# retries bootcmd. The A/B descriptor check prints what it refuses.
assert b'bootdelay=3' in kernel and b'bootretry=60' in kernel
assert 'CONFIG_BOOT_RETRY=y' in config and 'CONFIG_AUTOBOOT_KEYED=y' not in config
assert b'UFS boot-LUN check: ' in kernel
print(f'Marble U-Boot: Android v4, gzip payload {len(payload) - len(dtb)} bytes + DTB '
      f'{len(dtb)} bytes, image {len(blob)} bytes; config and DT verified')
