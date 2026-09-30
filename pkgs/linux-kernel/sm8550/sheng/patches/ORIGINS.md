# Sheng fork patch origins

Fork comparison: https://github.com/ianchb/sm8550-mainline/compare/500df175a7f9e6bc1a9c328590ca5150f84f9ff0...42f3b40c702abbc37c3a04c95af008cd283aeaf3

The records below retain the original author date, complete commit message, and all original sign-off/review trailers. Individual 7.3 patches list the contributing commit hashes and describe local adaptations separately. Inclusion in this origin index does not mean a commit was carried unchanged.

Omitted source commits: `435d3f9` (unused source config), `585d489` (DP audio fix already upstream), `ef2f794` (PCIe IOMMU mapping revert), `54188ce` (GPU_CC four-domain hunk conflicts with the 7.3 binding).

## 54ae6a494621ca845a956e73f7f67bc4e3f12717
Source: https://github.com/ianchb/sm8550-mainline/commit/54ae6a494621ca845a956e73f7f67bc4e3f12717
Author: map220v <map220v300@gmail.com>
Author date: 2024-08-24T10:19:16Z

Original message:

    SM8550: Add device tree for Xiaomi Pad 6S Pro 12.4


## 435d3f94c348a6bd2dcad753b8fc2c4d3df5b7df
Source: https://github.com/ianchb/sm8550-mainline/commit/435d3f94c348a6bd2dcad753b8fc2c4d3df5b7df
Author: map220v <map220v300@gmail.com>
Author date: 2024-08-24T10:19:37Z

Original message:

    SM8550: Add sm8550.config fragment


## 6f54af4f963df894d2970235a72e5f3560251b10
Source: https://github.com/ianchb/sm8550-mainline/commit/6f54af4f963df894d2970235a72e5f3560251b10
Author: Dmitry Baryshkov <dmitry.baryshkov@linaro.org>
Author date: 2023-06-04T21:44:33+03:00

Original message:

    drm/msm/dsi: change sync mode to sync on DSI0 rather than DSI1

    Change MSM DSI's sync-dual-dsi mode to resync on DSI0 rather than DSI1.

    Signed-off-by: Dmitry Baryshkov <dmitry.baryshkov@linaro.org>
    Signed-off-by: map220v <map220v300@gmail.com>


## eeb35550e5e555e65399f7d539c405f1eb9f08ce
Source: https://github.com/ianchb/sm8550-mainline/commit/eeb35550e5e555e65399f7d539c405f1eb9f08ce
Author: Jonathan Marek <jonathan@marek.ca>
Author date: 2023-11-14T17:58:33-05:00

Original message:

    drm/msm/dsi: support DSC configurations with slice_per_pkt > 1

    Add a dsc_slice_per_pkt field to mipi_dsi_device struct and the necessary
    changes to msm driver to support this field.

    Note that the removed "pkt_per_line = slice_per_intf * slice_per_pkt"
    comment is incorrect.

    Signed-off-by: Jonathan Marek <jonathan@marek.ca>
    Signed-off-by: map220v <map220v300@gmail.com>


## aca576c488afc7dc8719ccc84b6029f5b849dc62
Source: https://github.com/ianchb/sm8550-mainline/commit/aca576c488afc7dc8719ccc84b6029f5b849dc62
Author: map220v <map220v300@gmail.com>
Author date: 2024-08-24T10:31:44Z

Original message:

    drm/panel: Add panel driver for NT36532E based panels


## 980c62590f0f883647fa13a80d0be27e61c654e5
Source: https://github.com/ianchb/sm8550-mainline/commit/980c62590f0f883647fa13a80d0be27e61c654e5
Author: map220v <map220v300@gmail.com>
Author date: 2024-08-24T10:33:00Z

Original message:

    ath12k: Disable rfkill pin for now
    Fixes wifi hard block issue on Pad 6S Pro.


## 1ce8b16f6b6322445b7aace400180b87153f6631
Source: https://github.com/ianchb/sm8550-mainline/commit/1ce8b16f6b6322445b7aace400180b87153f6631
Author: map220v <map220v300@gmail.com>
Author date: 2024-08-24T10:34:27Z

Original message:

    ath12k: Generate random mac address if mac in eeprom is empty.


## 86f718f8e61e7b4d470f89da9e6cba700559cb99
Source: https://github.com/ianchb/sm8550-mainline/commit/86f718f8e61e7b4d470f89da9e6cba700559cb99
Author: map220v <map220v300@gmail.com>
Author date: 2024-08-24T10:36:13Z

Original message:

    qcom_battmgr: Add support for sm8550 xiaomi adsp changes


## 66828741c83c2929b68f57fce768a82382adc923
Source: https://github.com/ianchb/sm8550-mainline/commit/66828741c83c2929b68f57fce768a82382adc923
Author: map220v <map220v300@gmail.com>
Author date: 2024-09-03T12:04:19Z

Original message:

    ASoC: Add cs35l43 codec driver


## 25848897752cf664e8970d856902c5a2eed03ab8
Source: https://github.com/ianchb/sm8550-mainline/commit/25848897752cf664e8970d856902c5a2eed03ab8
Author: map220v <map220v300@gmail.com>
Author date: 2024-09-03T12:05:46Z

Original message:

    SHENG: Add cs35l43 nodes


## 46e9e4604c44ef30544ff1cf18cb59f684906a51
Source: https://github.com/ianchb/sm8550-mainline/commit/46e9e4604c44ef30544ff1cf18cb59f684906a51
Author: map220v <map220v300@gmail.com>
Author date: 2024-09-06T10:18:18Z

Original message:

    backlight: ktz8866: support paired controllers

    Mirror backlight register updates to the second controller used on sheng. Serialize access to the pair and make removal safe regardless of device unbind order.


## d4aad94087c8e23992071beb2465a5ca3a8ac6ae
Source: https://github.com/ianchb/sm8550-mainline/commit/d4aad94087c8e23992071beb2465a5ca3a8ac6ae
Author: map220v <map220v300@gmail.com>
Author date: 2024-09-06T10:18:48Z

Original message:

    SHENG: Add ktz8866 nodes


## 675ce13eea30a834596a9db87593548d5ce94b69
Source: https://github.com/ianchb/sm8550-mainline/commit/675ce13eea30a834596a9db87593548d5ce94b69
Author: map220v <map220v300@gmail.com>
Author date: 2024-09-06T10:18:57Z

Original message:

    drm/panel: nt36532e: Add backlight support


## 14fa324871914927db52ede601a86c99e4b97f90
Source: https://github.com/ianchb/sm8550-mainline/commit/14fa324871914927db52ede601a86c99e4b97f90
Author: map220v <map220v300@gmail.com>
Author date: 2024-09-06T10:43:44Z

Original message:

    SHENG: Remove splash_region node


## 76dae842473a742bfd92e7243bbf858f54fa36b6
Source: https://github.com/ianchb/sm8550-mainline/commit/76dae842473a742bfd92e7243bbf858f54fa36b6
Author: map220v <map220v300@gmail.com>
Author date: 2024-11-02T22:27:02Z

Original message:

    SHENG: Enable GPI DMA nodes


## 70924654407e959dd6b6e228853d59e4e33f39c9
Source: https://github.com/ianchb/sm8550-mainline/commit/70924654407e959dd6b6e228853d59e4e33f39c9
Author: map220v <map220v300@gmail.com>
Author date: 2024-11-02T22:32:49Z

Original message:

    Input: Add experimental nt36532e touch driver.
    Xiaomi's nt36532e firmware only reports raw capacitive data instead of regular touch events, so until I find out how to enable regular event parser, basic frame parser will be used, it supports only one finger and it's not really accurate.


## 4f80a541f84ca4e21e2f20d463697f50830e2a9e
Source: https://github.com/ianchb/sm8550-mainline/commit/4f80a541f84ca4e21e2f20d463697f50830e2a9e
Author: map220v <map220v300@gmail.com>
Author date: 2024-11-03T03:59:01Z

Original message:

    SHENG: Enable Flashlight and RGB LED support


## 63dd94ecd7fb757bb72075687c59fb7d65d87131
Source: https://github.com/ianchb/sm8550-mainline/commit/63dd94ecd7fb757bb72075687c59fb7d65d87131
Author: map220v <map220v300@gmail.com>
Author date: 2024-11-03T04:00:23Z

Original message:

    SHENG: Add Hall Effect Sensor for magnetic cover detection


## 5c2a8993d5ddf81e4de71fac845d731e4be47cf8
Source: https://github.com/ianchb/sm8550-mainline/commit/5c2a8993d5ddf81e4de71fac845d731e4be47cf8
Author: map220v <map220v300@gmail.com>
Author date: 2024-11-20T10:35:03Z

Original message:

    Input: nt36532e: Fix broken state when display isn't fully initialized


## c4ad4d27da349e890a2e06de969230bec04c580b
Source: https://github.com/ianchb/sm8550-mainline/commit/c4ad4d27da349e890a2e06de969230bec04c580b
Author: map220v <map220v300@gmail.com>
Author date: 2024-11-20T10:38:56Z

Original message:

    Input: nt36532e: Remove initial firmware update delay
    It's not required anymore, since panel state check was added.


## 950640c969e4a8f0ac45a1727bef1bfb676b747b
Source: https://github.com/ianchb/sm8550-mainline/commit/950640c969e4a8f0ac45a1727bef1bfb676b747b
Author: map220v <map220v300@gmail.com>
Author date: 2024-11-20T22:01:06Z

Original message:

    SHENG: Add wcd9380 and sound node


## e83ad096c7c3c155f326f9dfdc77419ba4e127d4
Source: https://github.com/ianchb/sm8550-mainline/commit/e83ad096c7c3c155f326f9dfdc77419ba4e127d4
Author: map220v <map220v300@gmail.com>
Author date: 2024-11-21T10:23:34Z

Original message:

    SHENG: use the PMU to power up bluetooth


## 95cb81c28a747fbe58637f35bf7c6899646b1224
Source: https://github.com/ianchb/sm8550-mainline/commit/95cb81c28a747fbe58637f35bf7c6899646b1224
Author: map220v <map220v300@gmail.com>
Author date: 2024-11-28T11:38:05Z

Original message:

    SHENG: Fix reserved memory regions and remove unused regions
    Test using memtester is successful with 99.8% memory usage, nothing crashed and no access errors in hypervisor log.


## bf804e88550305bc475f1623b8dfc93218d9b103
Source: https://github.com/ianchb/sm8550-mainline/commit/bf804e88550305bc475f1623b8dfc93218d9b103
Author: map220v <map220v300@gmail.com>
Author date: 2025-01-15T15:20:29Z

Original message:

    SM8550: Fix L2 cache for CPU2 and add cache sizes


## 28a018cdfcd2e6d0332c60dfe50329cecf5fe497
Source: https://github.com/ianchb/sm8550-mainline/commit/28a018cdfcd2e6d0332c60dfe50329cecf5fe497
Author: map220v <map220v300@gmail.com>
Author date: 2025-01-23T10:03:30Z

Original message:

    ASoC: qcom: sc8280xp: Add Secondary I2S support


## dec4dc4e55dbc2e6480cb56fd3100db10db81662
Source: https://github.com/ianchb/sm8550-mainline/commit/dec4dc4e55dbc2e6480cb56fd3100db10db81662
Author: map220v <map220v300@gmail.com>
Author date: 2025-01-23T10:27:17Z

Original message:

    SHENG: Add Secondary I2S


## e4f0e6ae7a27c2174f615f16574d201e200f267b
Source: https://github.com/ianchb/sm8550-mainline/commit/e4f0e6ae7a27c2174f615f16574d201e200f267b
Author: map220v <map220v300@gmail.com>
Author date: 2025-02-09T16:32:48Z

Original message:

    SM8550: Add missing master1 to cci1 node


## ad2f2257ac1b8608daf78f42fc481c77599fd33d
Source: https://github.com/ianchb/sm8550-mainline/commit/ad2f2257ac1b8608daf78f42fc481c77599fd33d
Author: map220v <map220v300@gmail.com>
Author date: 2025-02-09T16:34:49Z

Original message:

    SHENG: Fix supply for l6m and l7m regulators


## b230434fb3ffc4c6d27c1b32585669628a6145a2
Source: https://github.com/ianchb/sm8550-mainline/commit/b230434fb3ffc4c6d27c1b32585669628a6145a2
Author: map220v <map220v300@gmail.com>
Author date: 2025-02-15T12:49:23Z

Original message:

    media: i2c: Add OV02B1B image sensor driver


## 95d63f921e24c5a4b21b31fccbf9e9c390065ea8
Source: https://github.com/ianchb/sm8550-mainline/commit/95d63f921e24c5a4b21b31fccbf9e9c390065ea8
Author: map220v <map220v300@gmail.com>
Author date: 2025-02-15T12:50:28Z

Original message:

    media: i2c: Add OV32D40 image sensor driver


## db6fc1a0862887c53e0b14c3f73056a5b11dc695
Source: https://github.com/ianchb/sm8550-mainline/commit/db6fc1a0862887c53e0b14c3f73056a5b11dc695
Author: map220v <map220v300@gmail.com>
Author date: 2025-02-15T12:51:12Z

Original message:

    media: i2c: Add S5KJN1 image sensor driver


## 38ff9ffeef9615f8881e0e322ec0208a49309047
Source: https://github.com/ianchb/sm8550-mainline/commit/38ff9ffeef9615f8881e0e322ec0208a49309047
Author: map220v <map220v300@gmail.com>
Author date: 2025-02-15T13:25:24Z

Original message:

    SHENG: Add camera nodes and memory


## 65ff5f4fe0963dcf91e6e94c6d0d6d38432dfb50
Source: https://github.com/ianchb/sm8550-mainline/commit/65ff5f4fe0963dcf91e6e94c6d0d6d38432dfb50
Author: map220v <map220v300@gmail.com>
Author date: 2025-02-25T20:18:28Z

Original message:

    ath12k: Force Single Chip MLO support to fix firmware boot
    Booting new firmwares like "WLAN.HMT.1.1.c2-00259-QCAHMTSWPL_V1.0_V2.0_SILICONZ-1" is broken since https://github.com/torvalds/linux/commit/46d16f7e1d1413ad7ff99c1334d8874623717745 commit, so force enable single chip MLO like it was before.


## 1acf0452e7e24f686d5695b62ca1d366c9369519
Source: https://github.com/ianchb/sm8550-mainline/commit/1acf0452e7e24f686d5695b62ca1d366c9369519
Author: map220v <map220v300@gmail.com>
Author date: 2025-03-17T10:38:35Z

Original message:

    media: i2c: dw9768: Add initial focus, custom move delay and gt9764 support


## d1544c3c9537e35f3a0f47547d7a6fe8abcaf038
Source: https://github.com/ianchb/sm8550-mainline/commit/d1544c3c9537e35f3a0f47547d7a6fe8abcaf038
Author: map220v <map220v300@gmail.com>
Author date: 2025-03-13T18:47:32Z

Original message:

    SHENG: Add gt9764 node


## 038b6444ca29210d1c4f57c51fb0459688b11680
Source: https://github.com/ianchb/sm8550-mainline/commit/038b6444ca29210d1c4f57c51fb0459688b11680
Author: map220v <map220v300@gmail.com>
Author date: 2025-03-16T17:46:10Z

Original message:

    usb: typec: Add PS5169 linear redriver driver


## 6f45fa38972b812690141d230fd2c9938b4ebd19
Source: https://github.com/ianchb/sm8550-mainline/commit/6f45fa38972b812690141d230fd2c9938b4ebd19
Author: map220v <map220v300@gmail.com>
Author date: 2025-03-16T17:48:30Z

Original message:

    SHENG: Add ps5169 node


## 745755a042bde3ea32cbcc5353acdd046ffe093c
Source: https://github.com/ianchb/sm8550-mainline/commit/745755a042bde3ea32cbcc5353acdd046ffe093c
Author: map220v <map220v300@gmail.com>
Author date: 2025-04-04T16:16:44Z

Original message:

    drm/panel: nt36532e: Move DSI PPS commands to sheng_init_sequence and remove unused code


## 075bdf784848675c56e72d9af4bd8bb8b5cab12c
Source: https://github.com/ianchb/sm8550-mainline/commit/075bdf784848675c56e72d9af4bd8bb8b5cab12c
Author: map220v <map220v300@gmail.com>
Author date: 2025-04-04T16:27:52Z

Original message:

    drm/panel: nt36532e: Replace deprecated functions


## 8ae94f9e3ba563c493a140176d9fbfcb71966823
Source: https://github.com/ianchb/sm8550-mainline/commit/8ae94f9e3ba563c493a140176d9fbfcb71966823
Author: map220v <map220v300@gmail.com>
Author date: 2025-04-04T17:02:58Z

Original message:

    drm/panel: nt36532e: Add AVDD and AVEE supplies


## b4fb5849f227f0b0856cee9573a8d47cfcd1f545
Source: https://github.com/ianchb/sm8550-mainline/commit/b4fb5849f227f0b0856cee9573a8d47cfcd1f545
Author: map220v <map220v300@gmail.com>
Author date: 2025-04-07T12:26:26Z

Original message:

    ASoC: cs35l43: suppress log spam


## 54d1b2c49c390d05611a2a722f0b23eb694925c7
Source: https://github.com/ianchb/sm8550-mainline/commit/54d1b2c49c390d05611a2a722f0b23eb694925c7
Author: map220v <map220v300@gmail.com>
Author date: 2025-04-07T19:46:28Z

Original message:

    SHENG: Add iris node


## 6a0d5e86cedf541ec045a98bf11b67fd5ce7b6be
Source: https://github.com/ianchb/sm8550-mainline/commit/6a0d5e86cedf541ec045a98bf11b67fd5ce7b6be
Author: Jonathan Marek <jonathan@marek.ca>
Author date: 2024-10-07T19:54:09-04:00

Original message:

    ASoC: codecs: wcd938x: fix wcd938x_get_swr_port

    Controls can share the same "portidx" value (e.g. HPHL and HPHR), this
    leads to wcd938x_get_swr_port returning incorrect state. For example,
    when trying to enable both HPHL/HPHR with amixer: after enabling HPHL,
    HPHR will appear enabled and amixer skips writing to the control.

    This could be fixed by indexing with "ch_idx" instead, but lets just get
    rid of port_enable[] and check the ch_mask value of the port instead.

    Fixes: e8ba1e05bdc0 ("ASoC: codecs: wcd938x: add basic controls")
    Signed-off-by: Jonathan Marek <jonathan@marek.ca>
    Signed-off-by: map220v <map220v300@gmail.com>


## e8c36dc4da823aa8834cdeaf9fac5a7b1f2ce646
Source: https://github.com/ianchb/sm8550-mainline/commit/e8c36dc4da823aa8834cdeaf9fac5a7b1f2ce646
Author: map220v <map220v300@gmail.com>
Author date: 2025-06-15T18:28:36Z

Original message:

    HID: Add Nanosic WN8030 driver


## 9a493e85034c3ba0371d996d95a6ecb65fe9d9a7
Source: https://github.com/ianchb/sm8550-mainline/commit/9a493e85034c3ba0371d996d95a6ecb65fe9d9a7
Author: map220v <map220v300@gmail.com>
Author date: 2025-06-15T18:30:29Z

Original message:

    SHENG: Add nanosic_mcu node


## 2043091eebc390df69df95133a6788c7db4532c9
Source: https://github.com/ianchb/sm8550-mainline/commit/2043091eebc390df69df95133a6788c7db4532c9
Author: map220v <map220v300@gmail.com>
Author date: 2025-06-26T12:55:27Z

Original message:

    SHENG: Add rtc-offset node and enable RTC config


## 7e5fffeddcea29d386e57f3207d83884b6e66b14
Source: https://github.com/ianchb/sm8550-mainline/commit/7e5fffeddcea29d386e57f3207d83884b6e66b14
Author: map220v <map220v300@gmail.com>
Author date: 2025-07-13T21:21:18Z

Original message:

    Input: nt36532e: Use touch data from internal event buffer instead of host processing


## a72b124fb9f47f108e3870e965e8f3423955d1a8
Source: https://github.com/ianchb/sm8550-mainline/commit/a72b124fb9f47f108e3870e965e8f3423955d1a8
Author: map220v <map220v300@gmail.com>
Author date: 2025-08-08T17:19:50Z

Original message:

    SM8550: Add missing compute context banks to CDSP node


## fdf5a203d43ad2123a4b9a6ff088fd9b0f8d34c8
Source: https://github.com/ianchb/sm8550-mainline/commit/fdf5a203d43ad2123a4b9a6ff088fd9b0f8d34c8
Author: map220v <map220v300@gmail.com>
Author date: 2025-08-08T17:20:23Z

Original message:

    interconnect: qcom: sm8550: Enable QoS configuration


## 54188ce2809b2eb0a13ccdaaf96a85733f10f940
Source: https://github.com/ianchb/sm8550-mainline/commit/54188ce2809b2eb0a13ccdaaf96a85733f10f940
Author: Konrad Dybcio <konrad.dybcio@oss.qualcomm.com>
Author date: 2025-07-28T18:16:22+02:00

Original message:

    arm64: dts: qcom: sm8550: Describe GPU_CC power plumbing requirements

    A number of power rails must be powered on in order for GPU_CC to
    function. Ensure that's conveyed to the OS.

    Fixes: 9f7579423d2d ("arm64: dts: qcom: sm8550: Add graphics clock controller")
    Signed-off-by: Konrad Dybcio <konrad.dybcio@oss.qualcomm.com>
    Signed-off-by: map220v <map220v300@gmail.com>


## d218d8f6463e61a964674f965d0e06fd32d813d5
Source: https://github.com/ianchb/sm8550-mainline/commit/d218d8f6463e61a964674f965d0e06fd32d813d5
Author: map220v <map220v300@gmail.com>
Author date: 2025-10-14T07:51:50Z

Original message:

    drm/msm/a6xx: Enable IFPC on Adreno 740
    Same as overclocked Adreno 741


## 216006cdaae84bc3d5f6e6c34bbf6735c3cd7bb4
Source: https://github.com/ianchb/sm8550-mainline/commit/216006cdaae84bc3d5f6e6c34bbf6735c3cd7bb4
Author: map220v <map220v300@gmail.com>
Author date: 2025-11-15T10:21:07Z

Original message:

    Input: nt36532e: Fix randomly delayed touch exit events when quickly tapping


## 65f94e14cb0b42ef30c71dd4c541643c984cd708
Source: https://github.com/ianchb/sm8550-mainline/commit/65f94e14cb0b42ef30c71dd4c541643c984cd708
Author: map220v <map220v300@gmail.com>
Author date: 2026-01-27T10:49:47Z

Original message:

    Input: nt36532e: Remove data_buf and use proper address for reading point data


## 490cff4cdeb8c854db01a17f25fea91394a786c7
Source: https://github.com/ianchb/sm8550-mainline/commit/490cff4cdeb8c854db01a17f25fea91394a786c7
Author: map220v <map220v300@gmail.com>
Author date: 2026-02-23T12:12:08Z

Original message:

    HID: wn8030: Prevent MCU in keyboard from sleeping and improve suspend/remove safety


## 65721b2c57d3cad2bdc1fb16ec87cc3f4dd2cd9b
Source: https://github.com/ianchb/sm8550-mainline/commit/65721b2c57d3cad2bdc1fb16ec87cc3f4dd2cd9b
Author: map220v <map220v300@gmail.com>
Author date: 2026-02-23T12:12:37Z

Original message:

    HID: wn8030: Add offline authentication support


## efb92c293010f540c98e318ca7e4f2f7c67c9070
Source: https://github.com/ianchb/sm8550-mainline/commit/efb92c293010f540c98e318ca7e4f2f7c67c9070
Author: ianchb <i@4t.pw>
Author date: 2026-06-01T22:25:32+08:00

Original message:

    power: supply: qcom_battmgr: add Xiaomi MiPPS hooks


## e44b21886b5a4a5877480a9b9b1228d28ff125d0
Source: https://github.com/ianchb/sm8550-mainline/commit/e44b21886b5a4a5877480a9b9b1228d28ff125d0
Author: ianchb <i@4t.pw>
Author date: 2026-06-04T22:38:42+08:00

Original message:

    power: supply: qcom_battmgr: expose Xiaomi stylus power status

      Expose Xiaomi stylus battery, hall sensor, placement error, and wireless TX
      debug properties through the existing Xiaomi PMIC-glink battery attribute group.

      The hall values are used to identify whether the stylus is docked, while
      pen_soc and pen_place_err report battery and seating status.


## c471f75797deb6265b8ccf7072f21884883cb836
Source: https://github.com/ianchb/sm8550-mainline/commit/c471f75797deb6265b8ccf7072f21884883cb836
Author: ianchb <i@4t.pw>
Author date: 2026-06-06T10:25:16+08:00

Original message:

    power: supply: qcom_battmgr: report battery capacity from dual fuel gauges

      Xiaomi sheng uses two fuel gauges, and the standard BATT_CAPACITY
      reported by the battery manager can lag behind the actual pack state
      under discharge.  This makes the displayed battery percentage drop too
      slowly, then jump down after a reboot when the fuel-gauge state is
      refreshed.

      Use the Xiaomi FG1/FG2 remaining-capacity and full-charge-capacity
      properties to calculate POWER_SUPPLY_PROP_CAPACITY. Fall back to the
      standard BATT_CAPACITY request if the vendor fuel-gauge properties
      are unavailable.


## 892931635e3bf61bc33763e3bc4a3900d88f5776
Source: https://github.com/ianchb/sm8550-mainline/commit/892931635e3bf61bc33763e3bc4a3900d88f5776
Author: ianchb <i@4t.pw>
Author date: 2026-06-06T10:46:28+08:00

Original message:

    power: supply: qcom_battmgr: sort Xiaomi battery attributes


## 7bc4ad80e78c9625b0282308443ef0c7950c70b3
Source: https://github.com/ianchb/sm8550-mainline/commit/7bc4ad80e78c9625b0282308443ef0c7950c70b3
Author: ianchb <i@4t.pw>
Author date: 2026-06-06T20:54:09+08:00

Original message:

    media: i2c: sheng cameras: modernize runtime PM handling

      Update the sheng camera sensor drivers to follow the newer runtime PM
      lifecycle expected by current CAMSS/libcamera users.

      The old drivers powered sensors down immediately from s_stream(false).
      With PipeWire/libcamera keeping camera devices open and CAMSS now powering
      the pipeline around streaming, this caused repeated open/switch cycles to
      leave the sensor/CAMSS state inconsistent.

      Move ov02b1b, ov32d40 and s5kjn1-sheng to an autosuspend based model:
      power and identify the sensor during probe, cache the successful chip ID
      check, use delayed runtime suspend after stream stop, and retry chip ID
      reads during power-on. Also fix the power-on error paths so MCLK and
      regulators are unwound in the right order.


## 0a2d122c7acd9bc718740792d85c17868935d073
Source: https://github.com/ianchb/sm8550-mainline/commit/0a2d122c7acd9bc718740792d85c17868935d073
Author: ianchb <i@4t.pw>
Author date: 2026-06-07T17:13:54+08:00

Original message:

    drm/msm/dpu: reduce SM8550 clk_inefficiency_factor to unblock 144Hz

    The 144Hz mode requires 546 MHz core clock after the 105% factor and
    3d_merge adjustment, exceeding the SM8550 MDP OPP maximum of 514 MHz.
    This causes dpu_crtc_mode_valid() to reject the mode as MODE_CLOCK_HIGH,
    even though the hardware is capable of driving it.

    Reduce the factor from 105 to 98 to bring the adjusted clock (510 MHz)
    within range. This is a workaround — a proper fix (dynamic factor or
    per-mode override) is still under discussion upstream.

    Link: https://lkml.indiana.edu/hypermail/linux/kernel/2601.2/05058.html


## 3685432566c7f31d19787e7b14bbd9d2a6b284be
Source: https://github.com/ianchb/sm8550-mainline/commit/3685432566c7f31d19787e7b14bbd9d2a6b284be
Author: ianchb <i@4t.pw>
Author date: 2026-06-10T09:32:20+08:00

Original message:

    power: supply: qcom_battmgr: expose pen_mac_l/h


## 8610764f7b821692b1b6fd34b8c4020740b5f8a1
Source: https://github.com/ianchb/sm8550-mainline/commit/8610764f7b821692b1b6fd34b8c4020740b5f8a1
Author: ianchb <i@4t.pw>
Author date: 2026-06-15T09:40:21+08:00

Original message:

    arm64: dts: qcom: sm8550-xiaomi-sheng: enable HBR3 link rate for DP

    The DP controller's max link rate defaults to HBR2 (5.4 Gbps) when
    the 'link-frequencies' property is absent from the outbound endpoint.

    Add 'link-frequencies' with the HBR3 symbol rate (8.1 Gbps) to the
    DP output endpoint. The SM8550 QMP combo PHY and the DP controller
    both support HBR3 in hardware, as evidenced by the existing OPP table
    entry opp-810000000 and the qmp_v6_dp_serdes_tbl_hbr3 PHY table. This
    raises the availabe 4-lane bandwidth to ~25.9 Gbps, providing ample
    headroom for 4K@60Hz output.


## 4405046ea1702b809b40edb1214f818060b6057d
Source: https://github.com/ianchb/sm8550-mainline/commit/4405046ea1702b809b40edb1214f818060b6057d
Author: map220v <map220v300@gmail.com>
Author date: 2026-06-20T13:41:36Z

Original message:

    backlight: ktz8866: Fix to actually disable LCD Bias when panel is off
    KTZ8866 has only VIN as power supply, ENP and ENN gpios are used to control KTZ8866 LCD Bias.
    Also fix for dual KTZ8866 case. Don't enable LCD Bias for Slave, since LCD Bias is only provided by Master.


## 251f5ffc6f276233582e4275a131bae82d7965c0
Source: https://github.com/ianchb/sm8550-mainline/commit/251f5ffc6f276233582e4275a131bae82d7965c0
Author: ianchb <i@4t.pw>
Author date: 2026-06-24T17:28:36+08:00

Original message:

    arm64: dts: qcom: sm8550-xiaomi-sheng: use per-speaker CS35L43 DSP firmware


## 74d511754251399a7f878ce49d7ccb3892a7c051
Source: https://github.com/ianchb/sm8550-mainline/commit/74d511754251399a7f878ce49d7ccb3892a7c051
Author: ianchb <i@4t.pw>
Author date: 2026-06-29T15:16:37+08:00

Original message:

    HID: nanosic-wn8030: handle consumer control keyboard reports

    Signed-off-by: ianchb <i@4t.pw>


## da1e6f1f17dbb0117de399c9544899bf1bcdf9cb
Source: https://github.com/ianchb/sm8550-mainline/commit/da1e6f1f17dbb0117de399c9544899bf1bcdf9cb
Author: ianchb <i@4t.pw>
Author date: 2026-06-29T19:41:43+08:00

Original message:

    power: supply: qcom_battmgr: add Xiaomi keyboard plugin helper


## c49e8aaaf8eea87903d522a09330538a5d7361ca
Source: https://github.com/ianchb/sm8550-mainline/commit/c49e8aaaf8eea87903d522a09330538a5d7361ca
Author: ianchb <i@4t.pw>
Author date: 2026-06-29T19:42:32+08:00

Original message:

    HID: nanosic-wn8030: notify battmgr about pogo keyboard state


## 4e39eed69143ec93d5db811f63fffe1db2da6272
Source: https://github.com/ianchb/sm8550-mainline/commit/4e39eed69143ec93d5db811f63fffe1db2da6272
Author: ianchb <i@4t.pw>
Author date: 2026-06-29T22:24:20+08:00

Original message:

    ath12k: fix single-pdev regulatory frequency range update


## b9a4fae0df8f2c6f47f2c269e993b99e0df5540d
Source: https://github.com/ianchb/sm8550-mainline/commit/b9a4fae0df8f2c6f47f2c269e993b99e0df5540d
Author: ianchb <i@4t.pw>
Author date: 2026-06-30T18:58:52+08:00

Original message:

    soc: qcom: smp2p: Only reset inbound state on SSR


## d93a4d623c92230e0cc558cb68e9fec6322119a1
Source: https://github.com/ianchb/sm8550-mainline/commit/d93a4d623c92230e0cc558cb68e9fec6322119a1
Author: ianchb <i@4t.pw>
Author date: 2026-06-30T19:05:11+08:00

Original message:

    arm64: dts: qcom: sm8550-xiaomi-sheng: List all supported DP link rates


## 585d4895761b884995c6fbeb4444c569c9943c71
Source: https://github.com/ianchb/sm8550-mainline/commit/585d4895761b884995c6fbeb4444c569c9943c71
Author: Kumar Anurag <kumar.singh@oss.qualcomm.com>
Author date: 2026-06-16T08:12:52-07:00

Original message:

    drm/msm/dp: return 0 from audio_prepare when cable is disconnected

    PipeWire treats a non-zero return from prepare as fatal, marking the
    DP audio device as a dummy sink when the cable is unplugged. The
    active_stream_cnt guard already prevents any unclocked hardware access,
    so return success instead of -EINVAL when the link is not active.

    Signed-off-by: Kumar Anurag <kumar.singh@oss.qualcomm.com>
    Suggested-by: Srinivas Kandagatla <srinivas.kandagatla@oss.qualcomm.com>
    Signed-off-by: map220v <map220v300@gmail.com>


## 2fe6e9d78be11753ae7c15bef6c92b865011aff5
Source: https://github.com/ianchb/sm8550-mainline/commit/2fe6e9d78be11753ae7c15bef6c92b865011aff5
Author: map220v <map220v300@gmail.com>
Author date: 2026-06-30T08:29:01Z

Original message:

    SHENG: Add DisplayPort Playback


## a8e727ce479b0a0db7d4dc7eee3bc4743f4aed2e
Source: https://github.com/ianchb/sm8550-mainline/commit/a8e727ce479b0a0db7d4dc7eee3bc4743f4aed2e
Author: map220v <map220v300@gmail.com>
Author date: 2026-07-02T05:53:51Z

Original message:

    Input: nt36532e: Log fw history as error


## 5160e95a4a19b9329e65b9318f48fc3fdc5c9819
Source: https://github.com/ianchb/sm8550-mainline/commit/5160e95a4a19b9329e65b9318f48fc3fdc5c9819
Author: ianchb <i@4t.pw>
Author date: 2026-07-03T19:07:14+08:00

Original message:

    usb: typec: mux: initialize orientation switch array


## cc4d79e2806771472136528180e199240d5f454b
Source: https://github.com/ianchb/sm8550-mainline/commit/cc4d79e2806771472136528180e199240d5f454b
Author: ianchb <i@4t.pw>
Author date: 2026-07-13T18:45:54+08:00

Original message:

    arm64: dts: qcom: sm8550-xiaomi-sheng: use factory touch firmware


## 0d836d21a3c5b694959ef97481de8f7fb7586f49
Source: https://github.com/ianchb/sm8550-mainline/commit/0d836d21a3c5b694959ef97481de8f7fb7586f49
Author: ianchb <i@4t.pw>
Author date: 2026-07-13T18:48:35+08:00

Original message:

    input: touchscreen: nt36532e: expose raw THP frames to userspace

    Remove the processed touch and pen input paths and stop registering
    kernel input devices.

    Capture the complete NT36532E THP transport header and payload on each
    interrupt and expose timestamped records through a root-only FIFO. Append
    the existing event-region read without interpreting its contents.

    Signed-off-by: ianchb <i@4t.pw>


## 221ca986d370047597dfc59e6a492074ab982672
Source: https://github.com/ianchb/sm8550-mainline/commit/221ca986d370047597dfc59e6a492074ab982672
Author: ianchb <i@4t.pw>
Author date: 2026-07-16T00:52:58+08:00

Original message:

    input: touchscreen: nt36532e: reduce THP IRQ SPI transfers

    The THP IRQ path doesn't need to read the unused 761-byte event block now.


## 1004c6b0a188787a4b34a6736b3631205c7bfc57
Source: https://github.com/ianchb/sm8550-mainline/commit/1004c6b0a188787a4b34a6736b3631205c7bfc57
Author: ianchb <i@4t.pw>
Author date: 2026-07-16T19:26:58+08:00

Original message:

    input: touchscreen: nt36532e: restore charger mode handling

    Register a power-supply notifier and reproduce the stock commands when the external power state changes.


## 69692fbee3d8b162067ecc99f76d576ec6fa3a7d
Source: https://github.com/ianchb/sm8550-mainline/commit/69692fbee3d8b162067ecc99f76d576ec6fa3a7d
Author: ianchb <i@4t.pw>
Author date: 2026-07-18T12:40:52+08:00

Original message:

    input: touchscreen: nt36532e: signal THP firmware epochs


## 7832585dd4cfada45a51aece3d5f0d06f1e302f6
Source: https://github.com/ianchb/sm8550-mainline/commit/7832585dd4cfada45a51aece3d5f0d06f1e302f6
Author: ianchb <i@4t.pw>
Author date: 2026-07-18T15:31:55+08:00

Original message:

    arm64: dts: qcom: sm8550-xiaomi-sheng: add tablet mode Hall switch


## 91f677e23ed26dfa7dac2eb608422fa27c623f3a
Source: https://github.com/ianchb/sm8550-mainline/commit/91f677e23ed26dfa7dac2eb608422fa27c623f3a
Author: ianchb <i@4t.pw>
Author date: 2026-07-19T17:15:12+08:00

Original message:

    arm64: dts: qcom: sm8550-xiaomi-sheng: add fingerprint nodes


## 3df70886c852e3f3b6bc53b5ec8c84f5cb10a69f
Source: https://github.com/ianchb/sm8550-mainline/commit/3df70886c852e3f3b6bc53b5ec8c84f5cb10a69f
Author: ianchb <i@4t.pw>
Author date: 2026-07-19T17:19:44+08:00

Original message:

    fpc1553: add experimental FPC1553 platform driver


## e917f7f78d53c314f8a3809456682570cdd0cd17
Source: https://github.com/ianchb/sm8550-mainline/commit/e917f7f78d53c314f8a3809456682570cdd0cd17
Author: ianchb <i@4t.pw>
Author date: 2026-07-19T20:13:50+08:00

Original message:

    tee: qcom: preallocated 4194304-byte shared memory pool


## 3b90d7e013909dae0c25c80607b18d720e993aa8
Source: https://github.com/ianchb/sm8550-mainline/commit/3b90d7e013909dae0c25c80607b18d720e993aa8
Author: ianchb <i@4t.pw>
Author date: 2026-07-22T19:48:16+08:00

Original message:

    HID: nanosic-wn8030: add fold-angle control and mic-mute LED

    Expose keyboard accelerometer samples and an input-enable control for a
    userspace fold-angle policy. Register the microphone mute indicator as
    a standard LED class device so userspace can synchronize it with the
    desktop audio session.

    Signed-off-by: ianchb <i@4t.pw>


## a2777aab4bb683b077b962ebddedaa989a2b1d9e
Source: https://github.com/ianchb/sm8550-mainline/commit/a2777aab4bb683b077b962ebddedaa989a2b1d9e
Author: ianchb <i@4t.pw>
Author date: 2026-07-22T21:13:20+08:00

Original message:

    HID: nanosic-wn8030: defer mic-mute LED updates until key release


## 9887daa034b997b40f834855f626a45a0fb097ec
Source: https://github.com/ianchb/sm8550-mainline/commit/9887daa034b997b40f834855f626a45a0fb097ec
Author: ianchb <i@4t.pw>
Author date: 2026-07-23T21:57:34+08:00

Original message:

    input: touchscreen: nt36532e: allow setting stylus mode to 0/1/3


## 081de41e6fa3010f19432d46cc794075b50aca8b
Source: https://github.com/ianchb/sm8550-mainline/commit/081de41e6fa3010f19432d46cc794075b50aca8b
Author: ianchb <i@4t.pw>
Author date: 2026-07-26T00:19:09+08:00

Original message:

    arm64: dts: qcom: pmk8550: add SDAM 21 and 22


## bce09f68ea6e6b7e8e9c56fc78a5ffb66c7350ab
Source: https://github.com/ianchb/sm8550-mainline/commit/bce09f68ea6e6b7e8e9c56fc78a5ffb66c7350ab
Author: ianchb <i@4t.pw>
Author date: 2026-07-26T00:20:31+08:00

Original message:

    arm64: dts: qcom: sm8550-xiaomi-sheng: split RGB LEDs


## 0ab062e339f404b8c42913c6bdc8c69fc463595b
Source: https://github.com/ianchb/sm8550-mainline/commit/0ab062e339f404b8c42913c6bdc8c69fc463595b
Author: ianchb <i@4t.pw>
Author date: 2026-07-26T00:21:16+08:00

Original message:

    arm64: dts: qcom: sm8550-xiaomi-sheng: link rear camera flash


## 43f26d07947b0ab05553561e850d6a916ad80908
Source: https://github.com/ianchb/sm8550-mainline/commit/43f26d07947b0ab05553561e850d6a916ad80908
Author: ianchb <i@4t.pw>
Author date: 2026-07-26T00:21:39+08:00

Original message:

    media: dt-bindings: add camera activity LED properties

    Allow video devices to reference an activity LED and specify the
    brightness used while streaming. Unlike a privacy LED, an "activity
    LED" remains available for brightness control.

    Signed-off-by: ianchb <i@4t.pw>


## cbe4cd84372fa2040153885fa73d3e4aa30c6385
Source: https://github.com/ianchb/sm8550-mainline/commit/cbe4cd84372fa2040153885fa73d3e4aa30c6385
Author: ianchb <i@4t.pw>
Author date: 2026-07-26T00:22:30+08:00

Original message:

    media: v4l2-core: add camera activity LED support

    Privacy LEDs are intentionally locked against userspace control and
    driven at maximum brightness. Add a separate activity LED consumer for
    informational indicators that remain writable through the LED class
    interface.

    Signed-off-by: ianchb <i@4t.pw>


## bf25ef7250e8d35ca1c6fea4fd0e964796f5b770
Source: https://github.com/ianchb/sm8550-mainline/commit/bf25ef7250e8d35ca1c6fea4fd0e964796f5b770
Author: ianchb <i@4t.pw>
Author date: 2026-07-26T00:23:31+08:00

Original message:

    arm64: dts: qcom: sm8550-xiaomi-sheng: mirror camera LED policy

    The stock ROM sets the green LED to brightness 75 while either the
    front or rear camera is streaming, and allows overriding that value.

    Signed-off-by: ianchb <i@4t.pw>


## 24889bca68319132d12ec4b7eb250f70ec7696ce
Source: https://github.com/ianchb/sm8550-mainline/commit/24889bca68319132d12ec4b7eb250f70ec7696ce
Author: ianchb <i@4t.pw>
Author date: 2026-08-08T20:53:18+08:00

Original message:

    drm/msm: add sheng seamless panel mode switching


## c2802c86fccb438fbec0f81fd9e7ae39c04cb2fa
Source: https://github.com/ianchb/sm8550-mainline/commit/c2802c86fccb438fbec0f81fd9e7ae39c04cb2fa
Author: ianchb <i@4t.pw>
Author date: 2026-08-17T17:57:16+08:00

Original message:

    usb: typec: ps5169: enable USB mode on orientation attach


## 2a6fed47cd7e5c28678ba0904dac1c7e2ccda0a7
Source: https://github.com/ianchb/sm8550-mainline/commit/2a6fed47cd7e5c28678ba0904dac1c7e2ccda0a7
Author: ianchb <i@4t.pw>
Author date: 2026-08-19T23:15:42+08:00

Original message:

    drm/msm/dp: add external DP SST metadata support


## 2389392ab57369852af16bd4df87ff3c5ec03474
Source: https://github.com/ianchb/sm8550-mainline/commit/2389392ab57369852af16bd4df87ff3c5ec03474
Author: ianchb <i@4t.pw>
Author date: 2026-08-21T23:51:15+08:00

Original message:

    HID: nanosic-wn8030: add keyboard backlight LED support


## edfa200438319af0415709885a1145c37fc30581
Source: https://github.com/ianchb/sm8550-mainline/commit/edfa200438319af0415709885a1145c37fc30581
Author: ianchb <i@4t.pw>
Author date: 2026-08-26T09:11:05+08:00

Original message:

    drm/msm: raise SM8550 DPU clock and allow 700MHz display clocks


## 64cb2eeb22150eddea1f6c67ff70a5939c6cd32b
Source: https://github.com/ianchb/sm8550-mainline/commit/64cb2eeb22150eddea1f6c67ff70a5939c6cd32b
Author: ianchb <i@4t.pw>
Author date: 2026-08-27T01:31:39+08:00

Original message:

    drm/msm: add SST DSC and FEC support


## d3bb6d36b9fdfda0c091949ca9cef17bf1a87609
Source: https://github.com/ianchb/sm8550-mainline/commit/d3bb6d36b9fdfda0c091949ca9cef17bf1a87609
Author: Konrad Dybcio <konrad.dybcio@oss.qualcomm.com>
Author date: 2026-07-28T15:20:46+02:00

Original message:

    drm/msm/dp: Drop dev_pm_opp_set_rate(0)

    dev_pm_opp_set_rate(0) removes the vote specified in required-opps but
    does not actually park the clock, making it run without the necessary
    power backing. Drop the explicit calls to it.

    Fixes: c943b4948b58 ("drm/msm/dp: add displayPort driver support")
    Signed-off-by: Konrad Dybcio <konrad.dybcio@oss.qualcomm.com>
    Reviewed-by: Dmitry Baryshkov <dmitry.baryshkov@oss.qualcomm.com>
    Signed-off-by: map220v <map220v300@gmail.com>


## 04ad2e4507e7f2402b541dfcae76da7688fb5610
Source: https://github.com/ianchb/sm8550-mainline/commit/04ad2e4507e7f2402b541dfcae76da7688fb5610
Author: ianchb <i@4t.pw>
Author date: 2026-09-15T15:19:22+08:00

Original message:

    Reapply "drm/msm: dsi: fix PLL init in bonded mode"

    This reverts commit 5de981b7db1f509dfafe8e205b4d342436306e87.


## ef2f794ee6f0c28926466a051baf2d0457097d72
Source: https://github.com/ianchb/sm8550-mainline/commit/ef2f794ee6f0c28926466a051baf2d0457097d72
Author: ianchb <i@4t.pw>
Author date: 2026-09-16T11:00:37+08:00

Original message:

    Revert "arm64: dts: qcom: sm8550: Fix the PCIe iommu-map entries"

    This reverts commit 9eb128da8525a69575b38c87f47e04e2bc411df7.


## 42f3b40c702abbc37c3a04c95af008cd283aeaf3
Source: https://github.com/ianchb/sm8550-mainline/commit/42f3b40c702abbc37c3a04c95af008cd283aeaf3
Author: ianchb <i@4t.pw>
Author date: 2026-09-16T20:45:26+08:00

Original message:

    wifi: ath12k: load WCN7850 MAC address from wlan_mac.bin
