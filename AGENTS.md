# Unicorn workflow for future sessions

- Maintain device code and all kernel patches in this local repository.
- Personal Unicorn configuration is maintained locally in the sibling `/home/dwuggh/Projects/unicorn-config`. The phone `/etc/nixos` is a migration backup; the previous phone-only editing instruction is superseded.
- Initiate all Unicorn builds locally using `python3 tools/unicorn-build.py build <artifact>` (personal configuration). Use `--device build <artifact>` for this repository's device examples and `--device check <name>` for its ARM64 checks. `eval`, `plan`, and `sync` are also available; see `tools/unicorn-build.py --help`.
- The default is now workstation-led mixed building: the workstation cross-compiles ARM64 kernels and device components using native x86_64 tools; ordinary ARM64 userspace can use local QEMU and the LAN phone. The workstation and phone each have one build slot; `--cores 0` lets each task use all cores of its own builder (currently 16 workstation threads and 8 phone cores). One heavy task per machine avoids multiplying full-core jobs and memory pressure; software packages can still build simultaneously across both machines. This supersedes the earlier phone-only build rule. The helper snapshots tracked and untracked nonignored files without modifying Git staging.
- Nix daemon `builders` scheduling is used. Personal system and recovery kernels require `unicorn-workstation`, which is only available on this workstation; never advertise it on the phone. Repository example builds realise their base kernel locally before the mixed artifact build. Other packages can use both machines. Outputs, GC roots, and manifests now live on the workstation under `~/.local/state/unicorn-build`; old phone GC roots are retained. No manual source rsync or mount is needed.
- One-time workstation setup is `sudo python3 tools/setup-unicorn-builders.py --user dwuggh` (already applied on this workstation). It adds the dedicated feature and trusts this user without changing global build concurrency or global builder lists. The helper uses the verified LAN host key and existing SSH identity explicitly, so daemon SSH does not rely on root's SSH aliases.
- All phone SSH, transfer, and build connections use LAN alias `unicorn` (`192.168.3.94`), never USB `172.16.47.1`.
- Preserve the personal configuration's pinned shared input and unrelated lock revisions. Do not include ignored secrets in snapshots. Builds do not imply activation, flashing, rebooting, or display power cycling.
- Keep VT ioctl support. Treat physical display recovery separately from Niri IPC state.

These Unicorn-specific rules do not change other devices' build workflows.

- All-core defaults are now enabled: local `--max-jobs 1 --cores 0`, one native phone slot. Phone root SSH Nix processes read `/root/.config/nix/unicorn-builder.conf` (`cores = 0`); personal `phone.nix` also declares `nix.settings.cores = 0` for future activation. The local `--cores` flag controls workstation tasks; it is not forwarded as a phone core limit. Existing already-running builds keep their original core settings.

- Cross compilation is now the default: personal `buildSystem = "x86_64-linux"`, target/output namespace remains `aarch64-linux`. Repository example artifacts use `legacyPackages.x86_64-linux`. Never switch the kernel back to ARM64 tools under QEMU for workstation builds.

- Unicorn fingerprint development is deferred on this branch. Its implementation, firmware inputs and validation records are preserved on `archive/unicorn-fingerprint`; keep fingerprint services, packages and kernel additions off the active branch. Local reverse-engineering material remains under ignored `.work/unicorn/fingerprint`.
