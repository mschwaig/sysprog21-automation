#!/usr/bin/env nix-shell
#!nix-shell -i python -p "python310.withPackages(ps: [ ])"

import json
import glob
import pathlib
import shutil
import os
import stat

# ensure that submission repo is clean?
# build output from here?

def copy_writable(src, dst, *, follow_symlinks=True):
    if os.path.isdir(dst):
        dst = os.path.join(dst, os.path.basename(src))
    shutil.copyfile(src, dst, follow_symlinks=True)
    shutil.copymode(src, dst, follow_symlinks=True)
    # make all files user-writable
    os.chmod(dst, os.stat(dst).st_mode | stat.S_IWUSR)

cwd = pathlib.Path(os.getcwd())
result_dir = cwd / 'result'
state_dir = cwd / 'submissions'

# read step data from repo
with open(result_dir / 'metadata.json') as metadata_file:
    metadata = json.load(metadata_file)

copy_writable(result_dir / 'metadata.json', state_dir)
copy_writable(result_dir / 'status-report.html', state_dir)

rev = metadata["rev"]
steps = metadata["steps"]
print ("rev:" + rev)
for step in steps:
    print ("step:" + str(step))
    if True: #step["type"] == "REPEATABLE":
        for file in glob.glob('**/' + step["folder_name"], root_dir=result_dir, recursive=True):
            if (state_dir / file).exists():
                shutil.rmtree(state_dir / file)
            shutil.copytree(result_dir / file, state_dir / file, copy_function=copy_writable)
            # make all created directories user-writable
            for dirpath, _, _ in os.walk(state_dir/file):
                os.chmod(dirpath, os.stat(dirpath).st_mode | stat.S_IWUSR)
    elif step["type"] == "NOT_REPEATABLE" or step["type"] == "MANUAL":
        for file in glob.glob(str(result_dir / '**' / step["folder_name"]), recursive=True):
            if not (state_dir/file).exists():
                shutil.copytree(file, state_dir/file, copy_function=copy_writable)
                for dirpath, _, _ in os.walk(state_dir/file):
                    os.chmod(dirpath, os.stat(dirpath).st_mode | stat.S_IWUSR)

