#!/usr/bin/env bash

tag=`cat ./.dockertag`
arr=(${tag//\// })
repo=${arr[0]}
image=${arr[1]}

heading() {
  if [ -z "${2+x}" ]; then
    echo -e "\033[1;37m${1}\033[0m"
  else
    echo -e -n "\033[1;37m${1}\033[0m "
    echo $2
  fi
}

heading "Pushing ${image} to ${repo}..."
docker push $tag
