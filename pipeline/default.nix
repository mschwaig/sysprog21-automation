{ pkgs }:
with pkgs.lib;
rec {
  mkPipeline = { steps, inputs, meta, reference, previous_root }:
  let
    linkFarmWithPostBuild = (import ../utils.nix { inherit pkgs; }).linkFarmWithPostBuild;
    stepProperties =
      let
        firstStep = {
          name = "input";
          buildInputs = [];
          # set the input environment variable to the file containing the input
          text = ''
            cp "$__instance_path__" "$out/$(basename "$__instance_path__")"
          '';
        };
        func = index: step: {
          name = step.name;
          buildInputs = step.buildInputs;
          text = step.text;
          quantify = if step ? quantify then step.quantify else "";
          quantityName = if step ? quantityName then step.quantityName else "";
          type =
            let
              cases = [ "REPEATABLE" "NON_REPEATABLE" "MANUAL" ];
              typeOrDefault = if step ? type then step.type else "REPEATABLE";
              type = if any (x: x == typeOrDefault) cases then typeOrDefault else throw;
            in type;
          index = index;
          folder_name = "${toString index}_${step.name}";
        };
        in (imap0 func ([firstStep] ++ steps));

  referenceSteps = drop (if reference ? skip then reference.skip + 1 else 0) stepProperties;
  referenceSkip = take (if reference ? skip then reference.skip + 1 else 0) stepProperties;
  studentSteps = stepProperties;



  mkPipelineStep = prev: curr: pipeline_instance: rec {
    exports = prev.exports + ''
      export ${curr.name}="${drv}"
      export ${curr.name}Log="${drv.status}/log.txt"
      if [[ -e ${drv.status}/quantity ]]; then
          export ${curr.name}Quantity="$(cat ${drv.status}/quantity)"
      fi
    '';

    result = prev.result ++ [ {
      name = curr.folder_name;
      path = drv.out;
    } ];
    logs =
      let
        key =  removeSuffix "\n" (builtins.readFile "${drv.status}/status");
      in if builtins.elem key [ "OK" "FAIL" "OK_COPY" ] then prev.logs ++ [ {
        name = "${curr.folder_name}-log.txt";
        path = "${drv.status}/log.txt";
    } ] else prev.logs;

    statusReportData =
      let
        log_path = "\"${pipeline_instance.path_to}/logs/${curr.folder_name}-log.txt\"";
        out_path = "\"${pipeline_instance.path_to}/${curr.folder_name}\"";
        quantity =
          let
            quantityPath = "${drv.status}/quantity";
          in if pathExists quantityPath then builtins.readFile quantityPath else "";
        cases = {
          "OK" = "<td bgcolor=\"#90EE90\"><a href=${log_path}>view log</a>&nbsp;<a href=${out_path}>view result</a><br/>${quantity} ${curr.quantityName}</td>";
          "OK_COPY" = "<td bgcolor=\"#87CEFA\"><a href=${log_path}>view log</a>&nbsp;<a href=${out_path}>view result</a><br/>${quantity} ${curr.quantityName}</td>";
          "FAIL" = "<td bgcolor=\"#F08080\"><a href=${log_path}>view log</a>${if curr.type == "MANUAL" then "&nbsp;<a href=${out_path}>view result</a>" else ""}</td>";
          "PREV_FAIL" = "<td bgcolor=\"#D3D3D3\">SKIPPED</td>";
        };
        key =  removeSuffix "\n" (builtins.readFile "${drv.status}/status");
        lookup = if cases ? "${key}" then cases."${key}" else throw "invalid key '${key}'";
      in
      prev.statusReportData + ''
        ${lookup}
      '';

      drv = pkgs.runCommandLocal (curr.name + meta.name) {
        buildInputs = curr.buildInputs;
        outputs = [ "out" "status" ];
        text = curr.text;
        quantify = curr.quantify;
      passAsFile = [ "text" ] ++ (if curr.quantify != "" then [ "quantify" ] else []);
    }
      ''
      mkdir $status $out
      # check build state
      if ( ! (cmp -s -- "${./simple/ok}" "${prev.drv.status}/status" || cmp -s -- "${./simple/ok_copy}" "${prev.drv.status}/status")${if curr.type == "MANUAL" then " && false" else ""}); then
        ln -s ${./simple/skip_prev_fail} $status/status
        exit 0
      fi

      ${prev.exports}

      previous_output="${pipeline_instance.previous_output}/${curr.folder_name}"

      if [[ -e "$previous_output"${if curr.type != "MANUAL" then "/.manual" else ""} ]]; then
        echo "copying previous output" | tee $status/log.txt
        cp -r "$previous_output"/. $out
        ln -s ${./simple/ok_copy} $status/status
      else
        # run code
        if ! bash -euxo pipefail $textPath 2>&1 | tee $status/log.txt; then
          ln -s ${./simple/fail} $status/status
          exit 0
        fi
        ln -s ${./simple/ok} $status/status
      fi
      export log=$status/log.txt
        echo "computing quantities" | tee -a $status/log.txt
      if [[ -e $quantifyPath ]] && ! bash -euxo pipefail $quantifyPath 2>&1 | tee -a $status/log.txt| sed '/^+/d' | grep -E -x -m1 "[[:digit:]]+" | tee $status/quantity; then
        rm $status/status
        rm $status/quantity
        ln -s ${./simple/fail} $status/status
        exit 0
      fi
    '';
  };

  mkPipelineOfDrvsBaseCase = instance:
  rec {
    result = [];
    logs = [];
    statusReportData = ''
      <td>${instance.path_to}</td>
      ${concatMapStrings (_: "<td bgcolor=\"#D3D3D3\">SKIPPED</td>") instance.skip }
    '';
    exports = ''
      export __instance_path__="${instance.path}"
      ${concatMapStrings (stage: "export ${stage.name}=\"${instance.path}\"\n") instance.skip }
    '';
    drv.status = ./success;
  };


  mkPipelineOfDrvs = instance: steps: foldl (prev: curr: mkPipelineStep prev curr instance) (mkPipelineOfDrvsBaseCase instance) steps;

  referencePipeline =
  let
    pl = mkPipelineOfDrvs { name = "reference"; path = reference.src; previous_output = "${previous_root}/reference"; path_to = "reference"; skip = referenceSkip; } referenceSteps;
  in {
    name = "reference";
    path = pkgs.linkFarm "reference-pl" (pl.result ++ [{
        name = "logs";
        path = pkgs.linkFarm "reference-logs" pl.logs;
      }]);

    status = pl.statusReportData;
  };

  studentPipelines =
    let evalList = path_to_parent: input_list: map (input:
    let
      path_to = concatStringsSep "/" (path_to_parent ++ [ input.name ]);
      pl = mkPipelineOfDrvs (input // { previous_output = "${previous_root}/${path_to}"; path_to = path_to; skip = []; }) studentSteps;
    in {
      name = path_to;
      path = pkgs.linkFarm "${input.name}-pl" (pl.result ++ [{
        name = "logs";
        path = pkgs.linkFarm "${input.name}-logs" pl.logs;
      }]);
      status = pl.statusReportData;
    }) input_list;
    in
    if isList inputs then evalList [] inputs else flatten (mapAttrsToList (folder_name: list: (evalList [ folder_name ] list) ) inputs);

    statusReportDrv =
    let
      statusReportHeader = "<th>Path/Name/ID</th>" + (concatMapStrings (step: "<th>${step.name}</th>") stepProperties);
    in {
      name = "status-report.html";
      path = pkgs.runCommandLocal "compile-status-report" {
    } ''
      #mkdir $out
      cat << EOF > $out
      <table border="1">
      <tr>
        ${statusReportHeader}
      </tr>
      EOF
      cat << EOF >> $out
      <tr>
        ${referencePipeline.status}
      </tr>
      ${concatMapStrings (student: "<tr>${student.status}</tr>") studentPipelines}
      EOF
      cat << EOF >> $out
      </table>
      EOF
    '';
  };
  metadataDrv = {
    name = "metadata.json";
    path = pkgs.writeText "metadata.json" "${ builtins.toJSON {
      rev = meta.rev;
      steps = (map (step: {
        name = step.name;
        folder_name = step.folder_name;
        type = step.type;
      } ) stepProperties) ++ [{
        name = "logs";
        folder_name = "logs";
        type = "REPEATABLE";
      }];
    }}";
  };
  pipelineWithResults = studentPipelines ++ [ referencePipeline ];
  pipelineResult = linkFarmWithPostBuild meta.name pipelineWithResults ''
    cp ${statusReportDrv.path} ${escapeShellArg statusReportDrv.name}
    cp ${metadataDrv.path} ${escapeShellArg metadataDrv.name}
  '';
  in pipelineResult;

  pipelineTestOutput =
  let
  pipelineTestArgs = {
    meta = {
      name = "a3w21";
      rev = "asdfasdf";
    };

   # inputs = [
    inputs = {test =  [
      { name = "test"; path = ./testinput/test.zip; }
      { name = "test2"; path = ./testinput/test2.zip; }
 #   ];
    ];};

    reference = {
      skip = 1;
      src = ./testinput/ref-impl;
    };

    previous_root = "/var/empty";

    steps = [
      {
        name = "unpack";
        buildInputs = [ pkgs.unzip ];
        text = ''
          unzip $input/*
          mv test.c $out/
        '';
      }
      {
        name = "build";
        buildInputs = [ pkgs.gcc pkgs.binutils pkgs.gnumake ];
        text = ''
          cp $unpack/test.c .
          gcc -o $out/test test.c
        '';
        quantityName = "warnings";
        quantify = ''
          cat $log | ag "test.c:[[:digit:]]+:[[:digit:]]+:.warning:" | wc -l
        '';
      }
    ];
  };
  in mkPipeline pipelineTestArgs;
}
