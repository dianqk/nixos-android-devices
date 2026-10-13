#!/usr/bin/env python3
"""Inspect Aurora's RAM firmware envelope, device tree and resolved config.

Usage: python tests/aurora-uboot.py FIRMWARE_DIRECTORY ANDROID_IMAGE
Requires fdtget. Does not access a device.
"""
from pathlib import Path
import struct
import subprocess
import sys
import zlib

firmware, image = map(Path, sys.argv[1:])
blob = image.read_bytes()
def u32(offset):
    return struct.unpack_from('<I', blob, offset)[0]

assert blob[:8] == b'ANDROID!'
assert u32(36) == 4096 and u32(40) == 0
assert (u32(12), u32(20), u32(32)) == (0x8000, 0x1000000, 0x1e00000)
assert u32(24) == 0 and len(blob) <= 100 * 1024 * 1024
version = u32(44)
assert version == (14 << 25) | (26 << 4) | 2
kernel = (firmware / 'u-boot-nodtb.bin').read_bytes()
dtb = (firmware / 'u-boot.dtb').read_bytes()
gzip = zlib.decompressobj(31)
assert gzip.decompress(blob[4096:4096 + u32(8)]) == kernel
assert gzip.eof and gzip.unused_data == dtb
assert kernel[56:60] == b'ARM\x64'
assert struct.unpack_from('<Q', kernel, 8)[0] == 0
config = (firmware / '.config').read_text().splitlines()
for option in ['CLK_QCOM_SM8650', 'PINCTRL_QCOM_SM8650', 'UFS_QCOM',
               'PHY_QCOM_QMP_UFS', 'PHY_QCOM_SNPS_EUSB2', 'PHY_QCOM_PM8550B_EUSB2',
               'USB_FUNCTION_ACM', 'EFI_LOADER', 'CMD_BOOTEFI', 'CMD_BOOTI',
               'OF_LIBFDT_OVERLAY', 'QCOM_HYP_SMMU', 'SYSRESET_PSCI',
               'ENV_IS_NOWHERE', 'FS_FAT_HANDLE_SECTOR_SIZE_MISMATCH',
               'EFI_MOBILE_BOOT_ACTION_QCOM_AB', 'BUTTON_CMD', 'BUTTON_KEYBOARD',
               'BUTTON_QCOM_PMIC', 'BUTTON_GPIO', 'CMD_BOOTMENU']:
    assert f'CONFIG_{option}=y' in config, option
for option in ['PANIC_HANG', 'FASTBOOT_FLASH', 'EFI_CAPSULE_ON_DISK',
               'EFI_RUNTIME_UPDATE_CAPSULE']:
    assert f'CONFIG_{option}=y' not in config, option

def prop(node, name, kind='s'):
    return subprocess.check_output(['fdtget', '-t', kind, str(firmware / 'u-boot.dtb'),
                                    node, name], text=True).strip()

assert prop('/', 'compatible') == 'xiaomi,aurora qcom,sm8650'
assert prop('/', 'qcom,msm-id', 'x') == '22d 20000 22d 10000'
assert prop('/', 'qcom,board-id', 'x') == '8 0'
assert prop('/', 'xiaomi,miboard-id', 'x') == '4 0'
assert prop('/__symbols__', 'arch_timer') == '/timer'
assert prop(prop('/__symbols__', 'tlmm'), 'gpio-reserved-ranges', 'x') == '8 4 24 4 2a 1 4a 1'
assert prop('/reserved-memory/splash_region', 'reg', 'x') == '0 fc400000 0 2b00000'
assert prop('/reserved-memory/splash_region', 'no-map') == ''
fb = '/chosen/framebuffer@fc400000'
assert prop(fb, 'reg', 'x') == '0 fc400000 0 1194000'
assert prop(fb, 'width', 'u') == '1440'
assert prop(fb, 'height', 'u') == '3200'
assert prop(fb, 'stride', 'u') == '5760'
assert prop(fb, 'format') == 'a8r8g8b8'
assert 'CONFIG_NO_FB_CLEAR=y' in config
assert 'CONFIG_VIDEO_SIMPLE=y' in config

assert prop(prop('/__symbols__', 'adspslpi_mem'), 'reg', 'x') == '0 9df00000 0 4680000'
assert prop(prop('/__symbols__', 'hwfence_shbuf'), 'reg', 'x') == '0 ff100000 0 2dd000'
assert prop(prop('/__symbols__', 'oem_vm_mem'), 'reg', 'x') == '0 f7c00000 0 3800000'
assert prop('/soc@0/usb@a600000', 'dr_mode') == 'peripheral'
assert prop('/soc@0/usb@a600000', 'phy-names') == 'usb2-phy'
assert prop('/soc@0/usb@a600000', 'qcom,select-utmi-as-pipe-clk') == ''
repeater = prop('/__symbols__', 'pm8550b_eusb2_repeater')
assert prop('/soc@0/phy@88e3000', 'phys', 'x') == prop(repeater, 'phandle', 'x')
assert prop('/soc@0/phy@1d80000', 'compatible') == 'qcom,sm8650-qmp-ufs-phy'
assert prop('/soc@0/ufshc@1d84000', 'status') == 'okay'
assert b'bootdelay=0\0' in kernel
assert b'bootcmd=if test' in kernel and b'run boot_charger' in kernel
assert b'button_cmd_0_name=Volume Down\0' in kernel
assert b'stdin=serial,button-kbd\0' in kernel
assert b'bootmenu -1' in kernel
assert 'CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_CHARGER_PATH="/EFI/android-devices/charger.efi"' in config
for name, code in [('pon_pwrkey', '116'), ('pon_resin', '114')]:
    node = prop('/__symbols__', name)
    assert prop(node, 'status') == 'okay'
    assert prop(node, 'linux,code', 'u') == code
assert prop('/gpio-keys/key-volume-up', 'linux,code', 'u') == '115'
assert prop(prop('/__symbols__', 'volume_up_n'), 'power-source', 'u') == '1'
assert b'setenv stdout vidconsole,serial,usbacm' in kernel
assert b'preboot=run serial_gadget; run detect_boot_mode; scsi scan\0' in kernel
print(f'Aurora U-Boot artifact verified: {len(blob)} bytes, Android v0, ARM64/DT/USB/UFS/EFI configuration')

assert b'bootefi ${kernel_addr_r} ${fdt_addr_r}' in kernel
assert b'/EFI/BOOT/BOOTAA64.EFI' in kernel
