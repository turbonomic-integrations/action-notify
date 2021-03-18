#!/usr/bin/env bash

basedir=./
build=build
name=tr-action-notify
dest=tr-action-notify
tag=`cat ./.release`
repo=turbonomic-integrations/action-notify
archive="${name}-${tag}.tar.gz"
cwd=$(pwd)

heading() {
  if [ -z "${2+x}" ]; then
    echo -e "\033[1;37m${1}\033[0m"
  else
    echo -e -n "\033[1;37m${1}\033[0m "
    echo $2
  fi
}

heading "Archiving release $tag..."
cd "${basedir}/${build}" || exit
mkdir -p $dest
cp *.{yaml,sh} ./$dest

COPYFILE_DISABLE=1 tar -czvf $archive ./$dest/
echo

heading "Pushing $tag release to ${repo}..."
gh release upload $tag $archive --repo "$repo"
