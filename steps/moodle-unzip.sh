#!/usr/bin/env nix-shell
#!nix-shell -p pkgs.unzipNLS -i bash
unzip -I el_GR -O utf-8 "$@"
