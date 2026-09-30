#!/usr/bin/env python3
"""Inspect the built firmware and Android v2 envelope; no device access."""
import pathlib
import struct
import subprocess
import sys

firmware, image = map(pathlib.Path, sys.argv[1:])
blob = image.read_bytes()
u32 = lambda offset: struct.unpack_from('<I', blob, offset)[0]
aligned = lambda size: (size + 4095) // 4096 * 4096
assert blob[:8] == b'ANDROID!'
assert u32(36) == 4096 and u32(40) == 2
assert u32(1644) == 1660
assert len(blob) <= 96 * 1024 * 1024
kernel = (firmware / 'u-boot-nodtb.bin').read_bytes()
dtb = (firmware / 'u-boot.dtb').read_bytes()
payload_size = u32(8)
assert payload_size == max(len(kernel), 41289792)
assert blob[4096:4096 + len(kernel)] == kernel
assert not any(blob[4096 + len(kernel):4096 + payload_size])
assert kernel[56:60] == b'ARM\x64'
# ABL consumes the raw ARM64 header; a wrapped negative load offset is invalid.
text_offset, memory_size = struct.unpack_from('<QQ', kernel, 8)
assert text_offset == 0, f'Unexpected ARM64 Image text_offset: {text_offset:#x}'
assert len(kernel) <= memory_size <= payload_size < 96 * 1024 * 1024
assert u32(1648) == len(dtb)
assert struct.unpack_from('<Q', blob, 1652)[0] == 0x1f00000
start = 4096 + aligned(u32(8)) + aligned(u32(16)) + aligned(u32(24)) + aligned(u32(1632))
assert blob[start:start + len(dtb)] == dtb
config = (firmware / '.config').read_text().splitlines()
for option in ['CLK_QCOM_SM8450', 'PINCTRL_QCOM_SM8450', 'PHY_QCOM_QMP_UFS',
               'PHY_QCOM_SNPS_EUSB2', 'PHY_NXP_EUSB2', 'USB_FUNCTION_ACM',
               'EFI_LOADER', 'CMD_BOOTEFI', 'CMD_PMIC', 'FS_FAT_HANDLE_SECTOR_SIZE_MISMATCH']:
    assert f'CONFIG_{option}=y' in config, option
for option in ['EFI_RUNTIME_UPDATE_CAPSULE', 'EFI_CAPSULE_ON_DISK',
               'EFI_CAPSULE_FIRMWARE_RAW', 'EFI_CAPSULE_FIRMWARE_MANAGEMENT']:
    assert f'CONFIG_{option}=y' not in config, option

def prop(node, name, kind='s'):
    return subprocess.check_output(['fdtget', '-t', kind, str(firmware / 'u-boot.dtb'),
                                    node, name], text=True).strip()

assert prop('/', 'compatible') == 'lenovo,asphalt qcom,sm8475'
assert prop('/', 'region_country') == 'ROW'
assert prop('/', 'qcom,msm-id', 'x') == '213 10000'
assert prop('/chosen/framebuffer@b8000000', 'reg', 'x') == '0 b8000000 0 2b00000'
# ABL requires this exact path; Linux patch 0020 preserves the active PLL.
assert prop('/reserved-memory/splash_region', 'reg', 'x') == '0 b8000000 0 2b00000'
assert prop('/reserved-memory/splash_region', 'no-map', 'x') == ''
assert prop('/soc/phy@1d80000', 'compatible') == 'qcom,sm8475-qmp-ufs-phy'
assert prop('/soc/usb@a600000', 'dr_mode') == 'peripheral'
assert prop('/soc/usb@a600000', 'phy-names') == 'usb2-phy'
key_state = '/soc/spmi@c400000/pmic@1/gpio@8800/key-vol-up-state'
assert prop('/gpio-keys', 'pinctrl-names') == 'default'
assert prop('/gpio-keys', 'pinctrl-0', 'x') == prop(key_state, 'phandle', 'x')
assert prop(key_state, 'pins') == 'gpio6'
assert prop(key_state, 'function') == 'normal'
assert prop(key_state, 'input-enable', 'x') == ''
assert prop(key_state, 'bias-pull-up', 'x') == ''
assert prop(key_state, 'power-source', 'x') == '1'
assert b'linux-boot' in kernel and b'/EFI/BOOT/BOOTAA64.EFI' in kernel
print(f'Asphalt U-Boot: Android v2, ARM64 payload {len(kernel)} bytes, DTB {len(dtb)} bytes, image {len(blob)} bytes; config and DT verified')
