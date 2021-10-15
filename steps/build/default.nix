{ pkgs, sysprog-vm-pkgs }:
{ submission-ref, unpacked-assignment, ref-impl, src-name, binary-name }:

pkgs.stdenv.mkDerivation {
  name = "build" + submission-ref;

  preferLocalBuild = true;
  allowSubstitutes = false;
  outputs = [ "out" "log" ];

  srcs = pkgs.symlinkJoin {
    name = "whitelist-plus-provided";
    paths = [
      unpacked-assignment
      # provided reference files
      (pkgs.nix-gitignore.gitignoreSourcePure [
        src-name
      ] ref-impl)
    ];
  };
  # at least the "fortify" hardening option can cause
  # warnings that are not raised outside the build sandbox
  # so for now all hardening is disabled
  hardeningDisable = [ "all" ];
  buildInputs = with sysprog-vm-pkgs; [ gcc binutils gnumake ];
  buildPhase = ''
    make 2>&1 | tee make_output.log || true
  '';
  installPhase = ''
    mkdir -p $out/bin
    mkdir $log
    if [ -f ${binary-name} ]
    then
      cp ${binary-name} $out/bin/
    fi
    cp make_output.log $log/
  '';
  phases = [ "unpackPhase" "buildPhase" "installPhase" ];
}
