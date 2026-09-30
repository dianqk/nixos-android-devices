#!/usr/bin/env python3
"""Inspect Sheng's U-Boot display, key input and EFI image; no hardware access."""
import pathlib
import struct
import subprocess
import sys
import zlib

firmware, image = map(pathlib.Path, sys.argv[1:])
blob = image.read_bytes()
u32 = lambda offset: struct.unpack_from('<I', blob, offset)[0]
assert blob[:8] == b'ANDROID!'
assert u32(36) == 4096 and u32(40) == 0
assert u32(12) == 0x8000 and u32(20) == 0x1000000 and u32(32) == 0x1e00000
assert u32(24) == 0 and u32(28) == 0
assert len(blob) <= 192 * 1024 * 1024
kernel = (firmware / 'u-boot-nodtb.bin').read_bytes()
dtb = (firmware / 'u-boot.dtb').read_bytes()
gzip = zlib.decompressobj(16 + zlib.MAX_WBITS)
assert gzip.decompress(blob[4096:4096 + u32(8)]) == kernel
assert gzip.eof and gzip.unused_data == dtb
assert kernel[56:60] == b'ARM\x64'
assert struct.unpack_from('<Q', kernel, 8)[0] == 0, 'wrapped ARM64 text_offset'
config = (firmware / '.config').read_text().splitlines()
for option in ['CLK_QCOM_SM8550', 'PINCTRL_QCOM_SM8550', 'UFS_QCOM',
               'PHY_QCOM_QMP_UFS', 'PHY_QCOM_SNPS_EUSB2', 'PHY_QCOM_PM8550B_EUSB2',
               'PMIC_QCOM', 'CMD_PMIC', 'SPMI_MSM', 'USB_FUNCTION_ACM', 'EFI_LOADER',
               'CMD_BOOTEFI', 'FS_FAT_HANDLE_SECTOR_SIZE_MISMATCH', 'VIDEO',
               'VIDEO_SIMPLE', 'BUTTON_KEYBOARD', 'BUTTON_QCOM_PMIC',
               'BUTTON_REMAP_PHONE_KEYS', 'NO_FB_CLEAR']:
    assert f'CONFIG_{option}=y' in config, option
for option in ['EFI_RUNTIME_UPDATE_CAPSULE', 'EFI_CAPSULE_ON_DISK',
               'EFI_CAPSULE_FIRMWARE_RAW', 'EFI_CAPSULE_FIRMWARE_MANAGEMENT',
               'FASTBOOT_FLASH']:
    assert f'CONFIG_{option}=y' not in config, option

def prop(node, name, kind='s'):
    return subprocess.check_output(['fdtget', '-t', kind, str(firmware / 'u-boot.dtb'),
                                    node, name], text=True).strip()

assert prop('/', 'compatible') == 'xiaomi,sheng qcom,sm8550'
assert prop('/', 'qcom,msm-id', 'x') == '218 20000'
reserved_nodes = subprocess.check_output(
    ['fdtget', '-l', str(firmware / 'u-boot.dtb'), '/reserved-memory'],
    text=True,
).split()
assert 'splash_region@b8000000' in reserved_nodes
assert 'splash_region' not in reserved_nodes
assert prop('/reserved-memory/splash_region@b8000000', 'reg', 'x') == '0 b8000000 0 2b00000'
assert prop('/reserved-memory/splash_region@b8000000', 'no-map') == ''
framebuffer = '/chosen/framebuffer@b8000000'
assert prop(framebuffer, 'compatible') == 'simple-framebuffer'
assert prop(framebuffer, 'reg', 'x') == '0 b8000000 0 2b00000'
assert prop(framebuffer, 'width', 'u') == '3048'
assert prop(framebuffer, 'height', 'u') == '2032'
assert prop(framebuffer, 'stride', 'u') == '12192'
assert prop(framebuffer, 'format') == 'a8r8g8b8'
assert prop('/soc@0/phy@1d80000', 'compatible') == 'qcom,sm8550-qmp-ufs-phy'
assert prop('/soc@0/ufshc@1d84000', 'status') == 'okay'
assert prop('/soc@0/usb@a600000', 'dr_mode') == 'peripheral'
assert prop('/soc@0/usb@a600000', 'phy-names') == 'usb2-phy'
assert prop('/soc@0/usb@a600000', 'qcom,select-utmi-as-pipe-clk') == ''
assert prop('/soc@0/phy@88e3000', 'compatible') == 'qcom,sm8550-snps-eusb2-phy'
rptr = '/soc@0/spmi@c400000/pmic@7/phy@fd00'
assert prop(rptr, 'compatible') == 'qcom,pm8550b-eusb2-repeater'
assert prop('/soc@0/phy@88e3000', 'phys', 'x') == prop(rptr, 'phandle', 'x')
assert b'linux-boot' in kernel and b'/EFI/BOOT/BOOTAA64.EFI' in kernel
assert b'setenv stdout vidconsole,serial,usbacm' in kernel
print(f'Sheng U-Boot: Android v0, gzip ARM64 + DTB, image {len(blob)} bytes; UFS/USB/EFI framebuffer and key configuration verified')
