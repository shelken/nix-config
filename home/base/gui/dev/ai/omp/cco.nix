{
  lib,
  pkgs,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  bash,
  coreutils,
}:
stdenv.mkDerivation {
  pname = "cco";
  version = "unstable-2026-09-29";

  src = fetchFromGitHub {
    owner = "nikvdp";
    repo = "cco";
    rev = "658e99ce3ef90963b0a7d4443af16f4de983ea2c";
    hash = "sha256-m7z5ToSlYAWsOdnppXMPeRxz8Uh9BzxDCI/fbvl2dK8=";
  };

  patches = [ ./cco-seatbelt-order.patch ];

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/cco $out/bin
    cp -r * $out/libexec/cco/
    chmod +x $out/libexec/cco/cco $out/libexec/cco/sandbox
    makeWrapper $out/libexec/cco/cco $out/bin/cco \
      --prefix PATH : ${
        lib.makeBinPath (
          [
            bash
            coreutils
          ]
          ++ lib.optional stdenv.hostPlatform.isLinux pkgs.bubblewrap
        )
      }
    runHook postInstall
  '';

  meta = with lib; {
    description = "OS-native sandbox layer for AI coding agents (Seatbelt / bubblewrap)";
    homepage = "https://github.com/nikvdp/cco";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}
