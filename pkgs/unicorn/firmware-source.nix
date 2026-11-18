{ mkFirmwareArchive }:
# GPU, ADSP, SLPI and WLAN from dwuggh/firmware-xiaomi-unicorn at
# 1dd4c4d1eb9d1c00a63795fd7d897ec2a59a0b3b. The snapshot label records the
# verification date; the full official stock ROM build was not recorded.
mkFirmwareArchive {
  name = "unicorn-firmware-source";
  url = "https://github.com/dwuggh/firmware-xiaomi-unicorn/releases/download/snapshot-20261113/unicorn-firmware-snapshot-20261113.tar.zst";
  hash = "sha256-2CM8fcj30GB29kps4ps1cOHCVoz9/GhsC4fCAJgfMMI=";
}
