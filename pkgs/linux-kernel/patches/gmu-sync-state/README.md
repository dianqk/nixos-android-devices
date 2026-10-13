# GMU driver-core integration

Akhil P Oommen's [five-patch series](https://lore.kernel.org/r/20260513-gmu-sync-state-fix-v1-0-6e33e6aa9b4f@oss.qualcomm.com)
registers GMU as a component driver. Without a driver bound to the GMU node,
fw_devlink keeps the GCC and GPUCC `sync_state()` pending for the whole boot,
so boot-time power domains stay on. It is carried here as an upstream
proposal (RFT v1), not claimed to be merged. At import (2026-10-11) there was
no later revision and it was not in msm-next or linux-next; check the linked
thread for current upstream status. The original
author, dates, messages and sign-offs are preserved. Review tags for patches
1/3/5 and the series test tag come from replies in the linked thread; the
external test was on X1E80100.

The series is shared by the boards with an A6xx/A7xx GMU: Polaris (SDM845,
A630), Asphalt (SM8475, A730), Sheng (SM8550, A740) and Aurora (SM8650,
A750). Clover's A5xx has no GMU.

Patches 1–4 apply without changes. Patch 5 is rebased onto 7.3-rc5's scoped
`device_node` cleanup, performance-counter additions and updated sysprof
prototype; it applies unchanged to 7.3-rc6. Its GMU node reference remains
scoped; adding the old explicit `of_node_put()` would release it twice. The
series does not alter GPU operating points, GMU firmware or fenced-write
timeout thresholds. A successful bind does not establish suspend reliability
or resolve intermittent fenced-write latency.
