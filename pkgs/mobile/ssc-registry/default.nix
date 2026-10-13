{
  lib,
  runCommand,
  buildPackages,
  name,
  configDirectory,
  hwPlatform,
  socId,
  registryVersion,
  registryLayout ? "group",
}:
runCommand name { nativeBuildInputs = [ buildPackages.python3 ]; } ''
  python3 ${./generate.py} ${configDirectory} "$out" \
    --platform ${lib.escapeShellArg hwPlatform} --soc-id ${lib.escapeShellArg socId} \
    --version ${lib.escapeShellArg registryVersion} --layout ${lib.escapeShellArg registryLayout}
''
