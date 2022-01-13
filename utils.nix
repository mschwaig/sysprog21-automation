{ pkgs }:
with pkgs.lib;
{
  linkFarmWithPostBuild = name: entries: postBuild: pkgs.runCommand name { preferLocalBuild = true; allowSubstitutes = false; }
  ''mkdir -p $out
    cd $out
    ${concatMapStrings (x: ''
        mkdir -p "$(dirname ${escapeShellArg x.name})"
        ln -s ${escapeShellArg x.path} ${escapeShellArg x.name}
    '') entries}
    ${postBuild}
  '';
}
