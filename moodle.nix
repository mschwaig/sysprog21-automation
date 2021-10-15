{ pkgs }:
let
  strings = pkgs.lib.strings;
  zipListsWith = pkgs.lib.zipListsWith;
  filterAttrs = pkgs.lib.filterAttrs;
  last = pkgs.lib.last;
  nameValueListsToAttr = names: values: builtins.listToAttrs (zipListsWith (name: value: {inherit name value; }) names values);
in {
  parse-student-folder = { student-folder }:
  let
    student-folder-name = last (builtins.split "/" (toString student-folder));
    regex-result = builtins.match "([^_]+)_([[:digit:]]+)_assignsubmission_file_"  student-folder-name;
    student-data = nameValueListsToAttr [ "name" "id" ] (regex-result);
  in {
    id = student-data.id;
    name = student-data.name;
    folder-name = student-folder-name;
    drv-name-prefix = strings.sanitizeDerivationName (student-data.id);
  };

  extract-student-directories = { submissions-folder }:
    builtins.map
      (name: "${submissions-folder}/${name}")
      (builtins.attrNames
        (filterAttrs
            ( name: type: type == "directory" && name != ".git" )
            ( builtins.readDir submissions-folder )
        )
      );

  unzip-all = { moodle-zip }:
    pkgs.runCommand "moodle-unzip" { buildInputs = [ pkgs.unzipNLS ]; } ''
      unzip -I el_GR -O utf-8 ${moodle-zip} -d $out
    '';
}
