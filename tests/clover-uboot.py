#!/usr/bin/env python3
"""Inspect Clover firmware, storage wiring and Android envelope without hardware."""
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
assert u32(12) == 0x8000 and u32(20) == 0x1000000
assert u32(24) == 0 and u32(28) == 0  # No second-stage payload.
assert u32(32) == 0x100
assert len(blob) <= 64 * 1024 * 1024
kernel = (firmware / 'u-boot-nodtb.bin').read_bytes()
dtb = (firmware / 'u-boot.dtb').read_bytes()
gzip = zlib.decompressobj(16 + zlib.MAX_WBITS)
assert gzip.decompress(blob[4096:4096 + u32(8)]) == kernel
assert gzip.eof and gzip.unused_data == dtb
assert kernel[56:60] == b'ARM\x64'
config = (firmware / '.config').read_text().splitlines()
for option in ['CLK_QCOM_SDM660', 'PINCTRL_QCOM_SDM660', 'MMC_SDHCI_MSM',
               'PHY_QCOM_QUSB2', 'USB_FUNCTION_ACM', 'EFI_LOADER',
               'CMD_BOOTEFI', 'FS_FAT_HANDLE_SECTOR_SIZE_MISMATCH']:
    assert f'CONFIG_{option}=y' in config, option
for option in ['EFI_RUNTIME_UPDATE_CAPSULE', 'EFI_CAPSULE_ON_DISK',
               'EFI_CAPSULE_FIRMWARE_RAW', 'MMC_HS200_SUPPORT', 'MMC_HS400_SUPPORT']:
    assert f'CONFIG_{option}=y' not in config, option
assert 'CONFIG_FASTBOOT_FLASH_MMC_DEV=1' in config

def prop(node, name, kind='s'):
    return subprocess.check_output(['fdtget', '-t', kind, str(firmware / 'u-boot.dtb'),
                                    node, name], text=True).strip()

assert prop('/', 'compatible') == 'xiaomi,clover qcom,sdm660'
assert prop('/chosen/framebuffer@9d400000', 'reg', 'x') == '0 9d400000 0 8ca000'
for alias, address, limit in [('mmc1', 'c0c4000', '52000000'), ('mmc2', 'c084000', '50000000')]:
    node = '/soc@0/mmc@' + address
    assert prop('/aliases', alias) == node
    assert prop(node, 'status') == 'okay'
    assert prop(node, 'max-frequency', 'u') == limit
    props = subprocess.check_output(['fdtget', '-p', str(firmware / 'u-boot.dtb'), node], text=True).splitlines()
    assert 'power-domains' not in props
    assert 'mmc-hs200-1_8v' not in props and 'mmc-hs400-1_8v' not in props
assert prop('/soc@0/usb@a8f8800/usb@a800000', 'dr_mode') == 'peripheral'
assert b'part number mmc 1 system bootpart' in kernel
assert b'/EFI/BOOT/BOOTAA64.EFI' in kernel
print(f'Clover U-Boot: Android v0, gzip ARM64 + DTB, image {len(blob)} bytes; config, eMMC/microSD and USB DT verified')
