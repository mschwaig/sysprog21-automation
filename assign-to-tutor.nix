{ pkgs }:
{ moodle-zip, split, seed }:
with pkgs.lib;
let
  moodle = import ./moodle.nix { inherit pkgs; };
  numlib = import (builtins.fetchurl {
      url = https://gist.githubusercontent.com/corpix/f761c82c9d6fdbc1b3846b37e1020e11/raw/e0562a2374f7033914db044b1fa0946bb4a2095a/numbers.nix;
      sha256 = "1d4mb1kmhj11hsv737m6f9xrahria6d2si75xa4s5qijiyy2xmmm";
    }){ lib = pkgs.lib; };
  genshare = sharedef:
  (concatMap (tutor: builtins.genList(_: tutor.name) tutor.share) sharedef);
  share = genshare split;
  sharecount = length share;
  subdirs = folder:
    builtins.map
      (subdir: "${folder}/${subdir}")
      ( builtins.attrNames (builtins.readDir folder));
  id-from-student-folder = student-folder: (moodle.parse-student-folder { inherit student-folder; }).id;
  rnd-from-student-id = id: numlib.hexToDec (
    # use 8 hex digits for 32 bits of randomness
    substring 0 8 (builtins.hashString "sha1" (seed + id))
    );
  # TODO: find a way to make this the distribution less unstable
  # so that submissions are more evenly partitioned for every seed value
  rnd-from-student-folder = folder: rnd-from-student-id (id-from-student-folder folder);
in
  groupBy
    (folder: (elemAt share (mod (rnd-from-student-folder folder) sharecount)) )
    (subdirs (moodle.unzip-all { inherit moodle-zip; }))
