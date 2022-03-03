{ pkgs }:
let
  strings = pkgs.lib.strings;
  zipListsWith = pkgs.lib.zipListsWith;
  filterAttrs = pkgs.lib.filterAttrs;
  attrNames = pkgs.lib.attrNames;
  last = pkgs.lib.last;
  elemAt = pkgs.lib.elemAt;
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
    pkgs.runCommand "moodle-unzip" { buildInputs = [ pkgs.p7zip ]; } ''
      7z x ${moodle-zip} -o$out
    '';

  # TODO: ensure folder only contains one file
  studentZipFileName = student-folder: elemAt ( attrNames ( filterAttrs ( name: type: type == "regular")( builtins.readDir student-folder ) ) ) 0;
}
