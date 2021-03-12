#!/usr/bin/env bash

basedir=./
build=build
dest=container
namespace=turbointegrations
ver=1.0.0.dev1
relenv="prod"
team="turbointegrations"
name=tr-resize-notification
projectid=$(cat project.uuid)
buildid=$(git log -n 1 --pretty="%H" | cut -c1-8)
cwd=$(pwd)
deploy_user="turbo"
deploy_host="vmt-xl"
deploy_dest="~/${name}"

mkdir -p "${basedir}/${build}"
cd "${basedir}/${build}" || exit

opt_build=true
opt_deploy=false

heading() {
  if [ -z "${2+x}" ]; then
    echo -e "\033[1;37m${1}\033[0m"
  else
    echo -e -n "\033[1;37m${1}\033[0m "
    echo $2
  fi
}

keyvalue() {
  echo -e "\033[37m${1}: \033[36m${2}\033[0m"
}

spacer() {
  echo -e "\033[37m${1}\033[0m"
}

error() {
  echo -e "\033[31m${1}\033[0m"
}

buildcontainer() {
  local container="${2}:${3}"
  local archive="${2}-${3}"

  echo ""
  heading "Building $container ..."
  echo "---------------------------------------------------------------------- Start build -"
  docker build --no-cache -f "$1" -t "$container" "$4"
  code="$?"
  echo "------------------------------------------------------------------------ End build -"

  if [ "$code" -eq 1 ]; then
    error "Build failed"
    exit 1
  fi

  heading "Exporting $container ..."
  docker save "$container" > "${archive}.tar"

  xz -9z "${archive}.tar"
}

replace() {
  gsed -i "s/${2}/${3}/g" "$1"
}


while [[ $# -gt 0 ]]
do
  key="$1"

  case $key in
      --skip-build)
      opt_build=false
      shift
      ;;
      --deploy)
      opt_deploy=true
      shift
      ;;
      *)
      shift
      ;;
  esac
done

if $opt_build; then
  spacer "+----------------------------------------------------+"
  heading "  Build initiated"
  keyvalue "  Name       " ${name}
  keyvalue "  Version    " ${ver}
  keyvalue "  Build ID   " ${buildid}
  keyvalue "  Project ID " ${projectid}
  spacer "+----------------------------------------------------+"
  echo ""

  docker images &> /dev/null

  if [ "$?" -eq 1 ]; then
    heading "Docker daemon is not running, starting..."

    open --hide --background -a Docker

    until docker images &> /dev/null
    do
      sleep 1
    done
  fi

  heading "Cleaning up old builds..."
  rm -rf ./*
fi


heading "Updating base images..."
docker pull alpine
docker pull turbointegrations/base:1-alpine


heading "Copying resource files..."
cp ../src/docker/*.Dockerfile .
cp ../src/kube/*.yaml .

mkdir -p "$dest"
cp ../src/bash/* "$dest"
cp ../src/python/* "$dest"
mv "$dest/deploy.sh" .
chmod 744 deploy.sh

heading "Replacing stubs..."

for f in *.yaml deploy.sh;
do
  replace "$f" "@name@" "$name"
  replace "$f" "@team@" "$team"

  if [[ "$f" == *.yaml ]]; then
    replace "$f" "@projectid@" "\"$projectid\""
    replace "$f" "@buildid@" "\"$buildid\""
  else
    replace "$f" "@projectid@" "$projectid"
    replace "$f" "@buildid@" "$buildid"
  fi

  replace "$f" "@namespace@" "$namespace"
  replace "$f" "@version@" "$ver"
  replace "$f" "@env@" "$relenv"
done

if $opt_build; then
  buildcontainer 'base.Dockerfile' "$name" "$ver" "$dest"
fi

echo ''
heading "Build complete" $'\360\237\215\272'
echo ''

if $opt_deploy; then
  heading "Deploying build to ${deploy_host} ..."

  cd ..
  ssh "${deploy_user}"@"${deploy_host}" "mkdir -p ${deploy_dest}/"
  scp build/*.{yaml,sh} "${deploy_user}"@"${deploy_host}":"${deploy_dest}"

  count=`ls -1 build/*.xz 2>/dev/null | wc -l`
  if [[ $count -gt 0 ]]; then
    scp build/*.xz "${deploy_user}"@"${deploy_host}":"${deploy_dest}"
  fi
fi

cd "$cwd" || exit
