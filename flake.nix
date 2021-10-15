{
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixpkgs-unstable;
    sysprog-vm.url = github:mschwaig/sysprog-vm;
  };

  outputs = { self, nixpkgs, sysprog-vm }:

  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in
  with pkgs.lib;
  let
    sysprog-vm-pkgs = import sysprog-vm.inputs.nixpkgs { inherit system; };
    moodle = import ./moodle.nix { inherit pkgs; };

    # TODO: fix this properly! There could be other files in that folder
    # than comments.txt and the ZIP file.
    studentZipFileName = student-folder: elemAt ( attrNames ( filterAttrs ( name: type: type == "regular" && name != "comments.txt")( builtins.readDir student-folder ) ) ) 0;

    steps = {
      unpack = import ./steps/unpack { inherit pkgs; };

      build = import ./steps/build { inherit pkgs sysprog-vm-pkgs; };

      test = import ./steps/test {inherit pkgs sysprog-vm-pkgs; };

      grade = import ./steps/grade { inherit pkgs; };
    };

    organize-output-for-tutors = { submission-ref, assignment, student-feedback, src-name, binary-name }:
    pkgs.symlinkJoin {
      name = "tutor" + submission-ref;
      paths = [
        assignment.unpacked# ${src-name}
        assignment.built.out # ${binary-name}
        assignment.built.log
        assignment.tested.detailed
        assignment.tested.out # test_output_summary.txt
        assignment.graded.out # grade.csv
        assignment.graded.comments
        assignment.graded.warnings
        (pkgs.linkFarm submission-ref [
          { name = "unwanted_files"; path = assignment.unpacked.unwanted; }
          { name = "student_output"; path = assignment.tested.student_output; }
        ])
      ];
    };

    organize-output-for-students = { submission-ref, assignment, student-feedback, src-name, binary-name }:
    pkgs.symlinkJoin {
      name = "student" + submission-ref;
      paths = [
        assignment.built.log
        assignment.tested.out # test_output_summary.txt
        assignment.graded.out # grade.csv
        assignment.graded.comments
        (pkgs.linkFarm submission-ref [
          { name = "unwanted_files"; path = assignment.unpacked.unwanted; }
        ])
      ];
    };
  in {
    lib.mkAssignment = { binary-name, src-name, ref-impl, ref-data, config }:
      let
        server-binary = self.packages."${system}".server + "/bin/live-feedback-server";
        eval-script = (pkgs.writeScriptBin "eval-submission" ''
          #!${pkgs.runtimeShell}
          expr='import ${./eval-script-function.nix} { mkAssignment = (builtins.getFlake "${self}").lib.mkAssignment; binary-name="${binary-name}"; src-name="${src-name}"; ref-impl=${ref-impl}; ref-data=${ref-data}; config=${config}; student-submission = '"$1"';} '
          exec nix build --no-link -L  --impure --expr "$expr"
        '') + "/bin/eval-submission";
          assignToTutor = import ./assign-to-tutor.nix { inherit pkgs; };
      in rec {

      # command line access to the eval script is only needed for testing
      # eval = {
      #   type = "app";
      #   program = eval-script;
      # };

      server = {
        type = "app";
        program = (pkgs.writeScriptBin "run_server" ''
          ${server-binary} -e ${eval-script}
        '') + "/bin/run_server";
      };

      processSubmission = { submission-ref, student-submission, student-feedback, student-folder-name, organize-output }:
      let assignment =
      rec {
          unpacked = steps.unpack {
            inherit src-name student-submission submission-ref;
          };
          built = steps.build {
            inherit src-name binary-name ref-impl submission-ref;
            unpacked-assignment = unpacked;
          };
          tested = steps.test {
            inherit binary-name submission-ref ref-data;
            built-assignment = built;
            test-framework = ./tests;
            test-config = config;
          };
          graded = steps.grade {
            inherit student-feedback src-name student-folder-name;
            built-assignment = built;
          };
      };
        in organize-output {
            inherit binary-name submission-ref assignment student-feedback src-name;
          };

      buildAndTestAllStudentSubmissions = { submissions-folder-list }:
      pkgs.linkFarm "assignments"
        (forEach (concatMap (folder: moodle.extract-student-directories { submissions-folder=folder; }) submissions-folder-list) ( student-folder:
        let
          student-data = moodle.parse-student-folder { inherit student-folder; };
        in {
          name = student-data.folder-name;
          path = processSubmission {
            student-folder-name = student-data.folder-name;
            student-submission = "${student-folder}/${studentZipFileName student-folder}";
            student-feedback = "${student-folder}/comments.txt";
            submission-ref = student-data.drv-name-prefix;
          };
        }));

        # ingest TODO: make it easy to output changes to a git repo
        ingest = { moodle-zip, split, seed }:
        let
          groupedAssignments = assignToTutor {
            inherit moodle-zip split seed;
          };
        in
          pkgs.linkFarmFromDrvs "assignments"
          (mapAttrsToList (name: group:
            pkgs.linkFarm name
            (forEach group (student-folder:
            let
              student-data = moodle.parse-student-folder { inherit student-folder; };
            in {
              name = student-data.folder-name;
              path = processSubmission {
                student-folder-name = student-data.folder-name;
                student-submission = "${student-folder}/${studentZipFileName student-folder}";
                student-feedback = "${config}/criteria_preformatted.txt";
                submission-ref = student-data.drv-name-prefix;
                organize-output = organize-output-for-tutors;
              };
            }))) groupedAssignments);

        egress = { moodle-zip, split, seed, processed }:
        let
          groupedAssignments = assignToTutor {
            inherit moodle-zip split seed;
          };
        in
          pkgs.linkFarmFromDrvs "assignments"
          (mapAttrsToList (name: group:
            pkgs.linkFarm name
            (forEach group (student-folder:
            let
              student-data = moodle.parse-student-folder { inherit student-folder; };
            in {
              name = student-data.folder-name;
              path = processSubmission {
                student-folder-name = student-data.folder-name;
                student-submission = "${student-folder}/${studentZipFileName student-folder}";
                student-feedback = "${processed}/${name}/${student-data.folder-name}/comments.txt";
                submission-ref = student-data.drv-name-prefix;
                organize-output = organize-output-for-students;
              };
            }))) groupedAssignments);
    };

    # TODO: validate submission format?
    # TODO: validate if build succeeds?
    apps."x86_64-linux".moodle-unzip = {
      type = "app";
      program = toString ./steps/moodle-unzip.sh;
    };

    packages."x86_64-linux".server = pkgs.buildGoPackage rec {
      pname = "live-feedback-server";
      version = "0.1.0";

      goPackagePath = "github.com/mschwaig/live-feedback-server";

      src = ./live-feedback;
    };
  };
}
