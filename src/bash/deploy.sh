#!/usr/bin/env bash

# version: @version@
# build: @buildid@
shopt -s nullglob

deploy=1
name=@name@
app=@name@
relenv=@env@
team=@team@
namespace=@namespace@
ns=$(kubectl get namespaces | grep "$namespace" | cut -d' ' -f1)
pods=$(kubectl get pods -l app="$app" -n "$namespace" 2> /dev/null | wc -l)
opts=()

# these values are for displaying defaults only, changing them here will NOT
# change the system defaults in the container
_xlhost=api.turbonomic.svc.cluster.local
_xlport=8080
_xlssl=False
_xlactiontypes=""
_xlgroups=""
_xltags=""
_smtpport=25
_smtptls=False
#_emailto=""


heading() {
  echo -e "\033[1;37m${1}\033[0m"
}

invalid_option() {
  echo "Invalid option combination, check --help for details."
  exit 1
}

remove_deployment() {
  # local pods=$(kubectl get pods -l app="$app" -n "$namespace" 2> /dev/null | wc -l)
  #
  # if [[ "$pods" -gt 1 ]]; then
  #   heading 'Existing pods found'
  #   heading 'Waiting for pods to terminate...'
  #
  #   kubectl scale deployment --replicas=0 $name --timeout=1m -n "$namespace"
  #   kubectl delete pods -l app="$app" --wait=true -n "$namespace"
  #   sleep 30s
  # fi

  heading 'Checking for previously deployed resources...'
  #kubectl delete deployment -l app="$app" -n "$namespace" 2> /dev/null
  #kubectl delete configmap -l app="$app" -n "$namespace" 2> /dev/null
  #kubectl delete service -l app="$app" -n "$namespace" 2> /dev/null
  kubectl delete cronjob -l app="$app" -n "$namespace" 2> /dev/null
}

remove_images() {
  local imgcnt=$(sudo docker images | grep "$name" | wc -l)

  if [[ $imgcnt -ge 1 ]]; then
    heading 'Removing existing container image...'
    sudo docker images | grep "$name" | awk '{print $3}' | uniq | xargs sudo docker image rm -f
  fi
}

remove_auth() {
  kubectl delete secrets "${name}-auth" -n ${namespace} 2&> /dev/null
}

remove_config() {
  kubectl delete secrets "${name}-config" -n ${namespace} 2&> /dev/null
}

remove_secrets() {
  remove_auth
  remove_config
  #kubectl delete secrets -l app="$app" -n "$namespace"
}

uninstall() {
  remove_secrets
  remove_deployment
  remove_images
}

create_auth() {
  echo
  heading 'Creating Turbonomic API authentication secrets...'

  if [ -z "$xl_username" ]; then
    read -p 'Username: ' xl_username
  else
    echo "Username: '${xl_username}'"
  fi

  read -sp 'Password: ' _p

  auth=$(echo -n "$xl_username:$_p" | base64)
  echo

  kubectl create secret generic "${name}-auth" -n "$namespace" \
    --from-literal=TR_AUTH="$auth"

  unset _p
  unset auth

  kubectl label secret "${name}-auth" -n "$namespace" \
    environment="$relenv" \
    team="$team" \
    app="$app"
  echo
}

required_params() {
  while [[ $# -gt 0 ]]
  do
    key="$1"
    if [ -z "${!key}" ]; then
      echo "Import error: $1 is a required value."
      exit
    fi
    shift
  done
}

import_var() {
  if [ -n "$3" ]; then
    local __retvar=$1
    echo " - $2: $3"
    eval "$__retvar+=( --from-literal=${4}=\"${3}\" )"
  fi
}

create_config() {
  echo
  heading 'Configuring workload reporting settings'

  if [[ $import -eq 1 ]]; then
    echo "Turbonomic Instance"
    import_var opts 'Host' "$xl_host" 'TR_HOST'
    import_var opts 'Port' "$xl_port" 'TR_PORT'
    import_var opts 'SSL' "$xl_ssl" 'TR_SSL'
    import_var opts 'Groups' "$xl_groups" 'TR_GROUPS'
    import_var opts 'Email tags' "$xl_tags" 'TR_TAGS'
    import_var opts 'Action types' "$xl_actiontypes" 'TR_ACTION_TYPES'
    echo
    echo "SMTP Service"
    import_var opts 'Host' "$smtp_host" 'TR_SMTP_HOST'
    import_var opts 'Port' "$smtp_port" 'TR_SMTP_PORT'
    import_var opts 'TLS' "$smtp_tls" 'TR_SMTP_TLS'

    if [[ -n $smtp_username ]]; then
      echo " - Username: ${smtp_username}"
      read -sp "Password: " _p
      auth=$(echo -n "$smtp_username:$_p" | base64)
      opts+=( --from-literal=TR_SMTP_AUTH="$auth" )

      unset _p
      unset auth
      echo
    fi

    echo
    echo "Email Message"
    import_var opts 'From' "$email_from" 'TR_EMAIL_FROM'
    import_var opts 'To' "$email_to" 'TR_EMAIL_TO'
    import_var opts 'CC' "$email_cc" 'TR_EMAIL_CC'
    import_var opts 'BCC' "$email_bcc" 'TR_EMAIL_BCC'
    import_var opts 'Subject' "$email_subject" 'TR_EMAIL_SUBJECT'
    import_var opts 'Subject (Merged)' "$email_subject_multi" 'TR_EMAIL_SUBJECT_MULTI'
    import_var opts 'Body' "$email_body" 'TR_EMAIL_BODY'
    import_var opts 'Body as HTML' "$email_html" 'TR_EMAIL_HTML'
    import_var opts 'Entry header' "$email_part_header" 'TR_EMAIL_PART_HEADER'
    import_var opts 'Entry footer' "$email_part_footer" 'TR_EMAIL_PART_FOOTER'
    import_var opts 'Entry divider' "$email_div" 'TR_EMAIL_DIV'

  else
    echo 'Default values are shown in brackets [] where available. You may leave'
    echo 'the value empty to keep the default. Where no value is required, you may'
    echo 'also leave the value empty to set it to "null".'

    echo
    heading 'Turbonomic server settings'
    read -p 'Do you want to use Turbonomic server defaults (y/n)? ' ch
    if [ "$ch" == "${ch#[Yy]}" ]; then
      read -p "Hostname [${_xlhost}]: " xl_host
      xl_host="${xl_host:-$_xlhost}"
      if [ -n "$xl_host" ]; then  opts+=( --from-literal=TR_HOST="$xl_host" ); fi

      read -p 'Use SSL (y/n)? ' ch
      if [ "$ch" != "${ch#[Yy]}" ]; then
        opts+=( --from-literal=TR_SSL="True" )
        _xlport=443
      fi

      read -p "Port [${_xlport}]: " xl_port
      xl_port="${xl_port:-$_xlport}"
      opts+=( --from-literal=TR_PORT="$xl_port" )
    else
      xl_host="$_xlhost"
      xl_port="$_xlport"
      xl_ssl="$_xlssl"
      opts+=( --from-literal=TR_HOST="$xl_host" )
      opts+=( --from-literal=TR_PORT="$xl_port" )
    fi

    read -p "Turbo group(s) to monitor: " xl_groups
    xl_groups="${xl_groups:-$_xlgroups}"
    opts+=( --from-literal=TR_GROUPS="$xl_groups" )
    read -p "Turbo tag(s) for email recipient: " xl_tags
    xl_tags="${xl_tags:-$_xltags}"
    opts+=( --from-literal=TR_TAGS="$xl_tags" )
    read -p "Action Type(s): " xl_actiontypes
    xl_actiontypes="${xl_actiontypes:-$_xlactiontypes}"
    opts+=( --from-literal=TR_ACTION_TYPES="$xl_actiontypes" )

    echo
    heading 'SMTP settings'
    read -p 'SMTP hostname: ' smtp_host
    opts+=( --from-literal=TR_SMTP_HOST="$smtp_host" )

    read -p 'Use TLS (y/n)? ' ch
    if [ "$ch" != "${ch#[Yy]}" ]; then
      smtp_tls=True
      opts+=( --from-literal=TR_SMTP_TLS="True" )
      _smtpport=587
    fi

    smtp_tls="${smtp_tls:-$_smtptls}"

    read -p "SMTP port [${_smtpport}]: " smtp_port
    smtp_port="${smtp_port:-$_smtpport}"
    opts+=( --from-literal=TR_SMTP_PORT="$smtp_port" )

    read -p "Does '${smtp_host}' require authentication (y/n)? " ch
    if [ "$ch" != "${ch#[Yy]}" ]; then
      read -p 'Username: ' _u
      read -sp 'Password: ' _p
      auth=$(echo -n "$_u:$_p" | base64)
      opts+=( --from-literal=TR_SMTP_AUTH="$auth" )

      unset _u
      unset _p
      unset auth
      echo
    fi

    echo
    heading 'Email settings'
    read -p 'FROM address: ' email_from
    opts+=( --from-literal=TR_EMAIL_FROM="$email_from" )
    # read -p "TO address(es) [${_emailto}]: " email_to
    # if [ -n "$email_to" ]; then opts+=( --from-literal=TR_EMAIL_TO="$email_to" ); fi
    # read -p 'CC address(es): ' email_cc
    # if [ -n "$email_cc" ]; then  opts+=( --from-literal=TR_EMAIL_CC="$email_cc" ); fi
    # read -p 'BCC address(es): ' email_bcc
    # if [ -n "$email_bcc" ]; then  opts+=( --from-literal=TR_EMAIL_BCC="$email_bcc" ); fi
  fi

  required_params 'xl_host' 'xl_port' 'xl_ssl' 'smtp_host' 'smtp_port' 'smtp_tls' 'email_from' 'xl_groups' 'xl_tags' 'xl_actiontypes'

  echo
  kubectl create secret generic "${name}-config" -n "$namespace" "${opts[@]}"

  kubectl label secret "${name}-config" -n "$namespace" \
    environment="$relenv" \
    team="$team" \
    app="$app"
  echo
}

write_template() {
  cat > template <<'_END'
# All parameters are expressed as key=value pairs. Strings must be enclosed in
# single or double quotes, integer values may be unquoted. Lines preceeded with
# the hash # are comments and will be ignored. Optional values are commented out
# upon creation of this file. Passwords will be prompted for automatically if a
# corresponding username field is supplied.

#date="%Y-%m-%d"
#time="%H:%M:%S"
#timestamp="%Y-%m-%d %H:%M:%S"

# Turbonomic API parameters
# <!> If the Turbonomic server is not part of the same Kubernetes cluster or you
# are otherwise using the external IP you MUST enable SSL and use port 443 or the
# connection will fail.
xl_host="api.turbonomic.svc.cluster.local"
xl_port=8080
xl_ssl="False"
xl_username=""
xl_groups=""
xl_tags=""
xl_actiontypes=""

# SMTP service settings
# <!> If your SMTP server requires authentication, uncomment and provide a
# username below.
smtp_host=""
smtp_port=25
smtp_tls="False"
#smtp_username=""

# Email message settings
# <!> The TO address has been provided as a hard default. If you need to send to
# additional addresses use CC or BCC, if you need to override the TO address
# uncomment the following line. Comma separate multiple addresses.
#email_to=""
email_from=""
#email_cc=""
#email_bcc=""
# if True, the email body will be sent as HTML instead of plain text.
#email_html="True"
#email_subject=""
#email_subject_multi=""
#email_body=""
#email_div="<br /><hr><br />"
_END

}

deploy() {
  heading 'Deploying container image to local cache...'

  local extip=$(ip route get 1 | awk '{print $NF;exit}')

  for f in "${name}"*.tar.xz
  do
    sudo docker load < "$f"
  done

  if [ -z "${ns}" ]; then
    heading "Creating '$namespace' namesapce..."
    kubectl create namespace "$namespace"
  fi

  secrets=$(kubectl get secrets -n $namespace | grep "${name}-auth" | cut -d' ' -f1)
  if [ -z "${secrets}" ]; then
    create_auth
  fi
  secrets=$(kubectl get secrets -n $namespace | grep "${name}-config" | cut -d' ' -f1)
  if [ -z "${secrets}" ]; then
    create_config
  fi

  heading 'Applying deployment...'
  kubectl apply -f cron.yaml

  heading 'Done'
}

runjob() {
  heading 'Running single job instance...'

  kubectl create job "${name}-manual-run" --from=cronjob/${name} -n "${namespace}"

  echo
  echo 'You will need to cleanup the job manually.'
  echo "Example: kubectl delete job ${name}-manual-run -n ${namespace}"
}


while [[ $# -gt 0 ]]
do
  key="$1"

  case $key in
      -h|--help)
      echo "deploy.sh [OPTIONS]"
      echo ""
      echo "  --uninstall       Remove existing deployement completely, including secrets."
      echo ""
      echo "  --auth            Update the API credentials only."
      echo ""
      echo "  --keep-auth       Keep current API credentials, if set. Cannot be used with"
      echo "                    the --auth option."
      echo ""
      echo "  --config          Reconfigure reporting settings."
      echo ""
      echo "  --keep-config     Keep current reporting settings, if set. Cannot be used with"
      echo "                    the --config option."
      echo ""
      echo "  --import <file>   Reconfigure using the provided filename for <file>."
      echo ""
      echo "  --template        Dump a config template to disk named 'template'."
      echo ""
      echo "  --job             Run a stand-alone job after deployment."
      echo ""
      echo "  --job-only        Run a job only, do not redeploy."
      echo ""
      shift
      exit
      ;;
      --uninstall)
      heading "Removing '${name}' from ${namespace}"
      uninstall
      exit
      ;;
      --status)
      kubectl get pods -n "${namespace}"
      exit
      ;;
      --template)
      write_template
      exit
      ;;
      --terminal)
      kubectl exec -n "${namespace}" --stdin --tty $(kubectl get pods -n "${namespace}" | grep -e "${name}-manual-run\S*" -o) -- /bin/bash
      exit
      ;;
      --keep-auth)
      keepauth=1
      shift
      ;;
      --keep-config)
      keepconfig=1
      shift
      ;;
      --import)
      file="$2"
      source "$2"
      import=1
      shift
      shift
      ;;
      --auth)
      auth=1
      deploy=0
      shift
      ;;
      --config)
      config=1
      deploy=0
      shift
      ;;
      --job)
      job=1
      shift
      ;;
      --jobonly|--job-only)
      job=1
      deploy=0
      shift
      ;;
      *)
      shift
      ;;
  esac
done

echo ""

if [[ $auth -eq 1 ]]; then
  if [[ $keepauth -gt 0 ]]; then invalid_option; fi
  remove_auth
  create_auth
fi

if [[ $config -eq 1 ]]; then
  if [[ $keepconfig -gt 0 ]]; then invalid_option; fi
  remove_config
  create_config
fi

if [[ $deploy -eq 1 ]]; then
  heading "Preparing to deploy '${name}' to ${namespace}"
  if [ -z $keepauth ]; then remove_auth; fi
  if [ -z $keepconfig ]; then remove_config; fi
  remove_deployment
  deploy
fi

if [[ $job -eq 1 ]]; then
  runjob
fi