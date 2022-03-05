{ pkgs }:
with pkgs.lib;
{
  # TODO: convmv really should not be necessary here
  # it is unclear to me why the string input here (originally coming from builtins.readDir are not encoded correctly)
  linkFarmWithPostBuild = name: entries: postBuild: pkgs.runCommand name { preferLocalBuild = true; allowSubstitutes = false; }
  ''mkdir -p $out
    cd $out
    ${concatMapStrings (x: ''
        mkdir -p "$(dirname ${escapeShellArg x.name})"
        ln -s ${escapeShellArg x.path} ${escapeShellArg x.name}
        ${pkgs.convmv}/bin/convmv --notest -f iso-8859-1 -t UTF-8 ${escapeShellArg x.name}
    '') entries}
    ${postBuild}
  '';
}
