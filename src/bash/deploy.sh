#!/usr/bin/env bash

# version: @version@
# build: @buildid@
shopt -s nullglob

deploy=1
name=@name@
base_name=@name@
app=@name@
relenv=@env@
team=@team@
namespace=@namespace@
cron='cron.yaml'
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
  if [[ -z $1 ]]; then
    echo "Invalid option combination, check --help for details."
  else
    echo "Invalid option '$1', check --help for details."
  fi
  exit 1
}

remove_deployment() {
  heading 'Checking for previously deployed resources...'

  if [[ $1 -eq 1 ]]; then
    kubectl delete cronjob -l app="$app" -n "$namespace" 2> /dev/null
  else
    kubectl delete cronjob "$name" -n "$namespace" 2> /dev/null
  fi
}

remove_images() {
  local imgcnt=$(sudo docker images | grep "$base_name" | wc -l)

  if [[ $imgcnt -ge 1 ]]; then
    heading 'Removing existing container image...'
    sudo docker images | grep "$base_name" | awk '{print $3}' | uniq | xargs sudo docker image rm -f
  fi
}

remove_config() {
  if [[ $1 -eq 1 ]]; then
    kubectl delete secrets -l app="$app" -n "$namespace"
  else
    kubectl delete secrets "${name}-config" -n ${namespace} 2&> /dev/null
  fi
}

uninstall() {
  if [[ $1 -eq 1 ]]; then
    heading "Removing all '${app}' deployments from ${namespace}"
  else
    heading "Removing '${name}' from ${namespace}"
  fi

  remove_config $1
  remove_deployment $1

  local namecnt=$(kubectl get cronjob -l app="$app" -n $namespace | sed '1d' | wc -l)

  if [[ namecnt -gt 0 ]]; then
    echo "Container image appears to still be in use, skipping..."
  else
    remove_images
  fi
}

create_named_cron() {
  heading "Copying default config to named config..."
  echo "cron.yaml => ${1}"
  cp cron.yaml "${1}"

  sed -ri -e "s/(\s+name:) ${base_name}/\1 ${name}/gi" "$1"
  sed -ri -e "s/(\sgenerateName:) ${base_name}/\1 ${name}/gi" "$1"
  sed -ri -e "s/(\s+name:) ${base_name}-auth/\1 ${name}-auth/gi" "$1"
  sed -ri -e "s/(\s+name:) ${base_name}-config/\1 ${name}-config/gi" "$1"
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

# var, config name, value
set_var() {
  #local __retvar=$1
  #eval "$__retvar+=( --from-literal=${2}=\"${3}\" )"
  $opts+=( --from-literal=${2}="${3}" )
}

# user, pass, config name
auth_var() {
  auth=$(echo -n "$1:$2" | base64)
  set_var $3 $auth
}

# label, config name, value
import_var() {
  if [ -n "$3" ]; then
    if [ ! -z "$1" ]; then
      echo " - $1: $3"
    fi

    set_var $2 $3
  fi
}

# prompt, default, config name, required
prompt_var() {
  local value
  local label="$1"

  if [[ $4 -eq 1 ]]; then
    local label="${label}*"
  fi

  if [ -n "$2" ]; then
    read -p "$label [${2}]: " value
    value="${value:-$2}"
  else
    read -p "$label: " value
  fi

  if [ -n "$value" ]; then
    set_var $3 $value
  elif [[ $4 -eq 1 && -z "$value" ]]; then
    echo "Parameters marked with '*' are required."
    exit
  fi
}

create_config() {
  echo
  heading 'Configuring workload reporting settings'

  if [[ $import -eq 1 ]]; then
    echo "Turbonomic Instance"
    import_var 'Host' 'TR_HOST' "$xl_host"
    import_var 'Port' 'TR_PORT' "$xl_port"
    import_var 'SSL' 'TR_SSL' "$xl_ssl"
    import_var 'Groups' 'TR_GROUPS' "$xl_groups"
    import_var 'Email tags' 'TR_TAGS' "$xl_tags"
    import_var 'Action types' 'TR_ACTION_TYPES' "$xl_actiontypes"

    if [ -z "$xl_username" ]; then
      read -p 'Username: ' xl_username
    else
      echo "Username: '${xl_username}'"
    fi

    read -sp 'Password: ' _p
    auth_var 'TR_AUTH' $xl_username $_p
    unset _p
    unset auth

    echo
    echo "SMTP Service"
    import_var 'Host' 'TR_SMTP_HOST' "$smtp_host"
    import_var 'Port' 'TR_SMTP_PORT' "$smtp_port"
    import_var 'TLS' 'TR_SMTP_TLS' "$smtp_tls"

    if [[ -n $smtp_username ]]; then
      echo " - Username: ${smtp_username}"
      read -sp "Password: " _p
      auth_var 'TR_SMTP_AUTH' $smtp_username $_p
      unset _p
      unset auth
      echo
    fi

    echo
    echo "Email Message"
    import_var 'From' 'TR_EMAIL_FROM' "$email_from"
    import_var 'To' 'TR_EMAIL_TO' "$email_to"
    import_var 'CC' 'TR_EMAIL_CC' "$email_cc"
    import_var 'BCC' 'TR_EMAIL_BCC' "$email_bcc"
    import_var 'Subject' 'TR_EMAIL_SUBJECT' "$email_subject"
    import_var 'Subject (Merged)' 'TR_EMAIL_SUBJECT_MULTI' "$email_subject_multi"
    import_var 'Body' 'TR_EMAIL_BODY' "$email_body"
    import_var 'Body as HTML' 'TR_EMAIL_HTML' "$email_html"
    import_var 'Entry header' 'TR_EMAIL_PART_HEADER' "$email_part_header"
    import_var 'Entry footer' 'TR_EMAIL_PART_FOOTER' "$email_part_footer"
    import_var 'Entry divider' 'TR_EMAIL_DIV' "$email_div"

    required_params 'xl_host' 'xl_port' 'xl_ssl' 'smtp_host' 'smtp_port' 'smtp_tls' 'email_from' 'xl_groups' 'xl_tags' 'xl_actiontypes'
  else
    echo 'Default values are shown in brackets [] where available, and required'
    echo 'values are denoted with a *. You may leave the value empty to keep the'
    echo 'default. Where no value is required, you may also leave the value empty'
    echo 'to set it to "null".'

    echo
    heading 'Turbonomic server connection settings'
    read -p 'Do you want to use Turbonomic server defaults (y/n)? ' ch
    if [ "$ch" == "${ch#[Yy]}" ]; then
      prompt_var 'Hostname' "$_xlhost" 'TR_HOST'

      read -p 'Use SSL (y/n)? ' ch
      if [ "$ch" != "${ch#[Yy]}" ]; then
        set_var 'TR_SSL' 'True'
        _xlport=443
      fi

      prompt_var 'Port' "$_xlport" 'TR_PORT'
    else
      set_var 'TR_HOST' $_xlhost
      set_var 'TR_PORT' $_xlport
      set_var 'TR_SSL' $_xlssl
    fi

    echo
    heading 'Turbonomic server service account'
    read -p 'Username: ' xl_username
    read -sp 'Password: ' _p

    auth_var $xl_username $_p 'TR_AUTH'
    unset _p
    unset auth
    echo

    prompt_var 'Turbo group(s) to monitor' '' 'TR_GROUPS'
    prompt_var 'Turbo tag(s) for email recipient' '' 'TR_TAGS'
    prompt_var 'Action Type(s)' '' 'TR_ACTION_TYPES'

    echo
    heading 'SMTP settings'
    prompt_var 'SMTP hostname' '' 'TR_SMTP_HOST'

    read -p 'Use TLS (y/n)? ' ch
    if [ "$ch" != "${ch#[Yy]}" ]; then
      set_var 'TR_SMTP_TLS' 'True'
      _smtpport=587
    fi

    prompt_var 'SMTP Port' "$_smtpport" 'TR_SMTP_PORT'

    read -p "Does '${smtp_host}' require authentication (y/n)? " ch
    if [ "$ch" != "${ch#[Yy]}" ]; then
      read -p 'Username: ' _u
      read -sp 'Password: ' _p
      auth_var $_u $_p 'TR_SMTP_AUTH'
      unset _u
      unset _p
      unset auth
      echo
    fi

    echo
    heading 'Email settings'
    prompt_var 'FROM address' '' 'TR_EMAIL_FROM'
  fi

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

  for f in "$base_name"*.tar.xz
  do
    sudo docker load < "$f"
  done

  ns=$(kubectl get namespaces | grep "$namespace" | cut -d' ' -f1)
  if [ -z "$ns" ]; then
    heading "Creating '$namespace' namesapce..."
    kubectl create namespace "$namespace"
  fi

  secrets=$(kubectl get secrets -n "$namespace" | grep "${name}-config" | cut -d' ' -f1)
  if [ -z "$secrets" ]; then
    create_config
  fi

  if [ "$name" != "$base_name" ]; then
    heading "Applying named deployment ${name}..."
  else
    heading 'Applying deployment...'
  fi

  kubectl apply -f "$cron"
  heading 'Done'
}

runjob() {
  heading 'Running single job instance...'

  kubectl create job "${name}-manual-run" --from=cronjob/${name} -n "$namespace"

  echo
  echo 'You will need to cleanup the job manually.'
  echo "Example: kubectl delete job ${name}-manual-run -n ${namespace}"
}

### main ###

while [[ $# -gt 0 ]]
do
  key="$1"

  case $key in
      -h|--help)
      echo "deploy.sh [OPTIONS]"
      echo ""
      echo "  -n, --name            Install using the given object name. For multiple deployments."
      echo ""
      echo "  -c, --config <file>   Import the given file previously generated by --template as"
      echo "                        the configuration"
      echo ""
      echo "  -k, --keep-config     Keep current settings, if set. Cannot be used with the"
      echo "                        --update option."
      echo ""
      echo "  -t, --template        Dump a config template to disk named 'template'."
      echo ""
      echo "  -m, --make-cron       When used with --name this copies the cron.yaml to the given"
      echo "                        name for creating additional cronjobs."
      echo ""
      echo "  --run-job             Run a job only, do not redeploy."
      echo ""
      echo "  -u, --update          Update the configuration only, does not deploy the cronjob."
      echo ""
      echo "  --uninstall           Remove existing deployement completely, including secrets."
      echo "                        If the --all flag is also specified, all named deployments"
      echo "                        of the app will be removed."
      echo ""
      shift
      exit
      ;;
      -n|--name)
      name="$2"
      shift
      shift
      ;;
      --uninstall)
      uninstall=1
      shift
      ;;
      -a|--all)
      uninstall_all=1
      shift
      ;;
      --template)
      write_template
      exit
      ;;
      --terminal)
      kubectl exec -n "$namespace" --stdin --tty $(kubectl get pods -n "$namespace" | grep -e "${name}-manual-run\S*" -o) -- /bin/bash
      exit
      ;;
      --keep-config)
      keepconfig=1
      shift
      ;;
      -c|--config)
      import=1
      file="$2"
      source "$2"
      shift
      shift
      ;;
      -u|--update)
      update=1
      deploy=0
      shift
      ;;
      --copy-cron|--named-cron|--make-cron)
      makecron=1
      shift
      ;;
      --start-job|--run-job|--job-only)
      job=1
      deploy=0
      shift
      ;;
      --cron|--cronjob|--cronjobs)
      kubectl get cronjob -n "$namespace"
      exit
      ;;
      --job|--jobs)
      kubectl get jobs -n "$namespace"
      exit
      ;;
      --pod|--pods|--status)
      kubectl get pods -n "$namespace"
      exit
      ;;
      *)
      invalid_option $1
      ;;
  esac
done

echo ""

# set name first
if [ "$name" != "$base_name" ]; then
  echo "Using name '$name'..."
  cron="${name}-cron.yaml"
fi

if [[ $uninstall -eq 1 ]]; then
  uninstall $uninstall_all
  exit
fi

if [[ $update -eq 1 ]]; then
  if [[ $keepconfig -gt 0 ]]; then invalid_option; fi
  remove_config
  create_config
fi

if [[ $makecron -eq 1 ]]; then
  create_named_cron $cron
  exit
fi

if [[ $deploy -eq 1 ]]; then
  if [[ "$name" != "$base_name" && ! -f "$cron" ]]; then
    create_named_cron $cron
  fi

  if [ ! -f "$cron" ]; then
    echo "Required file '${cron}' missing"
    exit
  fi

  heading "Preparing to deploy '${name}' to ${namespace}"
  if [ -z $keepconfig ]; then remove_config; fi
  remove_deployment
  deploy
fi

if [[ $job -eq 1 ]]; then
  runjob
fi
