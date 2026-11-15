# MediaTek CCCI modem owner (the ccci_mdinit role: CCCI FS and RPC service,
# boot data, modem start) from the MT6895 mainline project, with a T880 board
# profile. Python standard library only; runs from the installed system.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  python3,
  util-linux,
}:
stdenvNoCC.mkDerivation {
  pname = "mtk-ccci-userspace";
  version = "0.1.0-unstable-2026-10-02";

  src = fetchFromGitHub {
    owner = "MT6895-Mainline";
    repo = "mtk-ccci-userspace";
    rev = "f6147b10cf7ef95932674506fbdfb7f3d67a1067";
    hash = "sha256-K0OPNcFUNa5rUIE2dCP1/83hhy0fZhDYOLi1RYSx8aY=";
  };

  patches = [
    # T880 launcher profile and per-drive FS root overrides (local)
    ./patches/0001-Add-a-t880-board-profile-and-per-drive-root-override.patch
    # AMMS DRDI copy service (local)
    ./patches/0002-Serve-the-modem-s-AMMS-DRDI-copy-requests.patch
    # MT6897 CMPT_Read2 and NV restore into the working copy (local)
    ./patches/0003-Serve-CMPT_Read2-0x1026-and-NV-restore-from-the-working-copy.patch
    # restart after a clean stop (local)
    ./patches/0004-Allow-a-start-after-a-clean-stop-md1-1.patch
    # Completed stop and failure reporting (local)
    ./patches/0005-Report-modem-stop-completion-and-failures.patch
  ];

  nativeBuildInputs = [ makeWrapper ];

  doCheck = true;
  nativeCheckInputs = [ python3 ];
  checkPhase = ''
    runHook preCheck
    python3 tests/test_runner.py
    runHook postCheck
  '';

  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm444 -t $out/libexec/mtk-ccci src/mtk_ccci_userspace/*.py
    install -Dm444 -t $out/share/mtk-ccci systemd/mtk-ccci-owner.service.example \
      config/mtk-ccci.env.example docs/*.md README.md
    # The launcher checks the deployment (pinned kernel, idle modem,
    # read-only NV mounts) before it runs the owner.
    makeWrapper ${lib.getExe python3} $out/bin/mtk-ccci-owner \
      --add-flags $out/libexec/mtk-ccci/start_owner.py \
      --prefix PATH : ${lib.makeBinPath [ util-linux ]}
    runHook postInstall
  '';

  meta = {
    description = "MediaTek CCCI modem owner (FS/RPC service, modem start) for MT6895/MT6897 boards";
    homepage = "https://github.com/MT6895-Mainline/mtk-ccci-userspace";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
    mainProgram = "mtk-ccci-owner";
  };
}
