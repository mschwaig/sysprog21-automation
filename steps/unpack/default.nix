{ pkgs }:
{ submission-ref, student-submission, src-name }:

# TODO: only support one format once students get instant feedback about their submission
pkgs.runCommandLocal ("unpack" + submission-ref) {
  buildInputs = [ pkgs.unzip pkgs.python3 ];
  outputs = [ "out" "unwanted" ];
} ''
  # unpack
  src="${student-submission}"
  if [[ $src == *.zip ]]; then
    unzip "$src"
    python ${./unzip-assignment.py}
  fi
  if [[ $src == *.tgz ]]; then
    tar zxvf "$src"
    python ${./unzip-assignment.py}
  fi
  ls -alh
  if [[ $src == *.c ]]; then
    cp "$src" ./${src-name}
  fi

  # produce output
  mkdir $out $unwanted
  cp ${src-name} $out/ || true

  # copy unwanted files
  # TODO: remove this when unwanted files can be rejected at submission time
  find . -type f ! -name ${src-name} ! -name env-vars -exec cp -t $unwanted {} +
''
