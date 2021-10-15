{ pkgs }:
{ student-feedback, built-assignment, src-name, student-folder-name }:
pkgs.runCommandLocal "grade" {
  buildInputs = [ pkgs.python pkgs.silver-searcher pkgs.dhall ];
  outputs = [ "out" "comments" "warnings" ];
} ''
  set -euxo pipefail
  cp "${student-feedback}" comments.txt
  warning_count="$(cat ${built-assignment.log}/make_output.log | ag "${src-name}:[[:digit:]]+:[[:digit:]]+:.warning:" | wc -l || true)"
  mkdir $out $comments $warnings
  echo "{ warnings = $warning_count }" > $warnings/warnings.dhall
  echo "${./.}/autograde.dhall (./comments.txt as Text) $warnings/warnings.dhall" | dhall text > $comments/comments.txt
  python ${./generate_grades_csv.py} $comments/comments.txt "${student-folder-name}" | tee $out/grade.csv
''

