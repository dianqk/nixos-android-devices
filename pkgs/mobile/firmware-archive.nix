# Unpack a released per-device firmware archive (tar.zst whose root is the
# payload tree, with a top-level SHA256SUMS) into a store directory.
{
  fetchurl,
  runCommand,
  pkgsBuildBuild,
}:
{
  name,
  url,
  hash,
}:
runCommand name { nativeBuildInputs = [ pkgsBuildBuild.zstd ]; } ''
  mkdir "$out"
  tar --zstd -xf ${fetchurl { inherit url hash; }} -C "$out"
  (cd "$out" && sha256sum -c --quiet SHA256SUMS)
''
