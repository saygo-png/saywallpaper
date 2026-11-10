{ mkDerivation, base, bytestring, containers, lib, relude, sayland
, stm, unix
}:
mkDerivation {
  pname = "saywallpaper";
  version = "0";
  src = ./.;
  isLibrary = false;
  isExecutable = true;
  executableHaskellDepends = [
    base bytestring containers relude sayland stm unix
  ];
  license = "unknown";
  mainProgram = "saywallpaper";
}
