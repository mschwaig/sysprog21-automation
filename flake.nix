{
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixpkgs-unstable;
    sysprog-vm.url = github:mschwaig/sysprog-vm;
  };

  outputs = { self, nixpkgs, sysprog-vm }:

  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
    pipelinelib = (import ./pipeline { inherit pkgs; });
    mkPipeline = pipelinelib.mkPipeline;
  in
  with pkgs.lib;
  let
    sysprog-vm-pkgs = import sysprog-vm.inputs.nixpkgs { inherit system; };
    moodle = import ./moodle.nix { inherit pkgs; };
  in {
    lib.mkAssignment = { meta, binary-name, src-name, reference, ref-data, config }:
    let
      commonPipelineArgs = {
        inherit meta reference;

        steps = [
          {
            name = "unpack";
            buildInputs = [ pkgs.unzip ];
            text = ''
              unzip "$input"/"$(ls $input)"
              find . -mindepth 2 -type f -exec mv -n '{}' . ';'
              mv ${src-name} $out/
            '';
          }
          {
            name = "build";
            buildInputs = with sysprog-vm-pkgs; [ gcc binutils gnumake pkgs.silver-searcher ];
            text = ''
              cp ${concatMapStrings (x: "${reference.src}/${x} ") reference.files} .
              cp $unpack/${src-name} .
              make
              cp ${binary-name} $out/
            '';
            quantityName = "warnings";
            quantify = ''
              ag -c "${src-name}:[[:digit:]]+:[[:digit:]]+:.warning:" $log || echo 0
            '';
          }
          {
            name = "test";
            type = "NON_REPEATABLE";
            buildInputs = [ pkgs.bats pkgs.silver-searcher ];
            text =
            let
              batsScript = pkgs.writeScriptBin "test_cases.bats" ''
                #!${pkgs.bats}/bin/bats
                ${builtins.readFile (config + "/test_cases.bats")}
              '';
            in ''
              export BINARY=$build/${binary-name}
              export REF_DATA=${ref-data}
              mkdir $out/student_output
              export STUDENT_OUTPUT=$out/student_output
              # TODO: make bats return value 0 on failing tests
              timeout 10 ${batsScript}/bin/test_cases.bats --formatter tap13 || true
            '';
            #cat $detailed/test_output.log | grep "^[^[:space:]]" > $out/test_output_summary.log
            quantityName = "failing tests";
            quantify = ''
              ag -c "^not ok" $log || echo 0
            '';
          }
          {
            name = "grade";
            type = "MANUAL";
            buildInputs = [ pkgs.cue ];
            text = ''
              cat ${config}/correction-template.cue > correction.cue
              if [[ -n "''${buildQuantity-}" ]]; then
                cat << EOF >>  warnings.cue
                  if $buildQuantity >= 20 {
                  deductions: warnings: points: 20
                  }
                  if $buildQuantity < 20 {
                  deductions: warnings: points: $buildQuantity
                  }
              EOF
                cat warnings.cue
                cue eval correction.cue warnings.cue > tmp.cue
                mv tmp.cue correction.cue
              fi
              cat correction.cue ${./steps/grade/schema-to-template.cue} > tmp.cue
              mv tmp.cue correction.cue
              cp correction.cue $out/correction.cue
            '';
            quantityName = "points";
            quantify = ''
              cue eval -c $out/correction.cue ${config}/correction-template.cue ${./steps/grade/correction-schema.cue} -e point_total
            '';
          }
          {
            name = "output";
            buildInputs = [];
            text = ''
              # copy results from previous stages to output
              # this is what gets returned to students

              cp $buildLog $out/make_output.txt
              cat $testLog | grep "^[^[:space:]]" > $out/test_output_summary.txt
              cp $grade/correction.cue $out/correction.cue
            '';
          }
        ];
      };
      in rec {

      # command line access to the eval script is only needed for testing
      # eval = {
      #   type = "app";
      #   program = eval-script;
      # };

      server = {
        type = "app";
        program =
          let
            server-binary = self.packages."${system}".server + "/bin/live-feedback-server";
            eval-script = (pkgs.writeScriptBin "eval-submission" ''
              #!${pkgs.runtimeShell}
              expr='import ${./eval-script-function.nix} { mkAssignment = (builtins.getFlake "${self}").lib.mkAssignment; binary-name="${binary-name}"; src-name="${src-name}"; ref-impl=${ref-impl}; ref-data=${ref-data}; config=${config}; student-submission = '"$1"';} '
              exec nix build --no-link -L  --impure --expr "$expr"
            '') + "/bin/eval-submission";
          in (pkgs.writeScriptBin "run_server" ''
          ${server-binary} -e ${eval-script}
        '') + "/bin/run_server";
      };

      processSubmission = { submission-ref, student-submission, student-feedback, student-folder-name }:
      mkPipeline (commonPipelineArgs // {
        inputs = [ {
          name = submission-ref;
          path = student-submission;
        } ];
        previous_root = "/var/empty";
      });

      ingest = { moodle-zip, split, seed, processed }:
      let
        assignToTutor = import ./assign-to-tutor.nix { inherit pkgs; };
        groupedAssignments = assignToTutor {
          inherit moodle-zip split seed;
        };
      in mkPipeline (commonPipelineArgs // {
        inputs = groupedAssignments;
        previous_root = processed;
      });
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

    defaultPackage."x86_64-linux" = pipelinelib.pipelineTestOutput;
  };
}
