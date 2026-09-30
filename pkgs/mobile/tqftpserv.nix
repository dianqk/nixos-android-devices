# v1.2 accepts the modem's /readonly/vendor firmware request paths.
# Keep Nixpkgs' profile-path substitution unless a board opts out.
{ tqftpserv, fetchFromGitHub }:
tqftpserv.overrideAttrs (_: {
  version = "1.2";
  src = fetchFromGitHub {
    owner = "linux-msm";
    repo = "tqftpserv";
    rev = "v1.2";
    hash = "sha256-tXxiunBMbmHcko4tqgMXvOEZrMeqk4quybV1PukW0U0=";
  };
})
