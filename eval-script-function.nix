{ mkAssignment, meta, binary-name, src-names, reference, ref-data, config, student-submission }:
let
  assignmentlib = mkAssignment {
    inherit meta binary-name src-names reference ref-data config;
  };
in
  assignmentlib.processSubmission {
    # copy input path to the store. See:
    # https://stackoverflow.com/a/43850372
    # TODO: make sure file is stored content-addressed and output file hash
    # See also: https://github.com/NixOS/nix/issues/1528
    inherit student-submission;
    submission-ref = "Anonymous";
    student-feedback = "${config}/criteria_preformatted.txt";
    student-folder-name = "Anonymous";
  }
