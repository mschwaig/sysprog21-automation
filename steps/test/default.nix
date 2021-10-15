{ pkgs, sysprog-vm-pkgs }:
{ submission-ref, built-assignment, test-framework, test-config, ref-data, binary-name }:
let
  batsScript = pkgs.writeScriptBin "test_cases.bats" ''
    #!${pkgs.bats}/bin/bats
    ${builtins.readFile (test-config + "/test_cases.bats")}
  '';
in
pkgs.runCommandLocal ("test" + submission-ref) {
  buildInputs = [ built-assignment pkgs.python3 sysprog-vm-pkgs.valgrind pkgs.bats ref-data ];
  outputs = [ "out" "detailed" "student_output" ];
    } ''
    # run tests
    mkdir $out $detailed $student_output
    export BINARY=${built-assignment}/bin/${binary-name}
    export REF_DATA=${ref-data}
    export STUDENT_OUTPUT=$student_output
    timeout 10 ${batsScript}/bin/test_cases.bats --formatter tap13 2>&1 | tee $detailed/test_output.log || true
    cat $detailed/test_output.log | grep "^[^[:space:]]" > $out/test_output_summary.log
''
