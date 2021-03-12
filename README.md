# Action Notify - Scheduled Email Notification of Turbonomic Actions

## Table of Contents

1. [Description](#description)
2. [Requirements](#requirements)
3. [Build](#build)
4. [Installation](#installation)
   1. [Linux Installs](#linux)
   2. [Other Installs](#manual)
5. [Uninstallation](#uninstallation)

******


## Description <a name="description"></a>
Sends email notifications of pending generated actions on one or more groups to
a tagged workload owner, at a prescribed schedule via cron. Groups, tags, and
action types are configurable.

******


## Requirements <a name="requirements"></a>

- Turbonimic XL 8.0.4 or higher.

- External SMTP service.

- Kubernetes equivalent environment for deployment if not using the Turbonomic XL OVA.

******


## Build <a name="build"></a>

:warning: \
Because the container generated for this package is published publicly, this package
is designed to be immediately usable from the published scripts. If for any
reason you need to build from source you will have to publish your own container
and update the deployment scripts to use your local or separately published image.

Should you need to build from source for any reason, you will need a docker compatible
container build engine. This project is designed by default to use Docker Desktop.
Any engine which can consume a dockerfile and generate a compatible container
should be usable, provided you update the build command appropriately.

<details>
<summary>Build Instructions</summary>
<br />

Version updates are handled by the Python package [bump2version](https://github.com/c4urself/bump2version). This is not strictly required unless using the included
bump-*.sh scripts. The version can be manually set in the `build.sh`, however,
the two methods cannot be mixed.

To build from source, run the `build.sh`. The build script is designed to be run
from the project root in the following manner:

```bash
bin/build.sh
```

All build output will be placed in the `build/` folder.

### Build settings

Build settings are found at the top of the `build.sh` and must be configured for
your specific use case. The parameters are as follows:

- **basedir** - Project directory
- **build** - Build folder name
- **dest** - Container build cache subfolder name
- **namespace** - Deployment Kubernetes namespace
- **ver** - Build version
- **relenv** - Environment label
- **team** - Build team label
- **name** - Project deployment name
- **projectid** - Project ID label
- **buildid** - Specific build ID label

The following options are only used with the `--deploy` mode, for transferring
the build output to a designated test machine.
- **deploy_user** - Username (pre-shared key authentication required)
- **deploy_host** - Target test system
- **deploy_dest** - Folder on target test system to deposit files (must exist)

</details>

******

## Installation <a name="installation"></a>

The email notification reporting can be installed in either a scripted or manual
manner as required. Installation is based off of the standard Turbonomic XL OVA,
which deploys Kubernetes systems running Dockershim, and may need to be adjusted
for your environment.


### Linux Installation <a name="linux"></a>

```bash
./deploys.sh
```

The 'turbointegrations' namespace will be created if it does not exist. The user will be prompted for the Turbonomic API credentials and other configuration paramters as required.
A configuration file may be imported using the `--import <filename>` option. A
template for the import config may be dumped using the `--template` option. See
`deploy.sh --help` for complete options.


#### Command Options
```bash
deploy.sh [OPTIONS]

  --uninstall       Remove existing deployement completely, including secrets.

  --auth            Update the API credentials only.

  --keep-auth       Keep current API credentials, if set.

  --config          Reconfigure reporting settings.

  --keep-config     Keep current reporting settings, if set.

  --import <file>   Reconfigure using the provided filename for <file>.

  --template        Dump a config template to disk named 'template'.

  --job             Run a stand-alone job after deployment.

  --job-only        Run a job only, do not redeploy.
```


#### Configuration
Configuration is completed interactively, or via an import configuration using
the template from the `--template` option.


##### Configuration Template
```
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
#email_html="False"
```


### Manual Installation <a name="manual"></a>

#### Create namespace if it does not exist
```bash
kubectl create namespace turbointegrations
```

#### Encode API credentials
Replace `<user>` and `<pass>` with the username and password respectively

##### Linux
```bash
auth=$(echo -n "<user>:<pass>" | base64)
```

##### Windows Powershell
```
$auth = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("test"))
```

#### Create secret
```bash
kubectl create secret generic tr-action-notification-auth -n turbointegrations \
  --from-literal=TR_AUTH="$auth"

kubectl label secret tr-action-notification-auth -n turbointegrations \
  environment=prod \
  team="turbointegrations" \
  app="tr-action-notification"
```

#### Available Configuration Parameters

The following list of parameters are available to be configured for the report
via the `tr-action-notification-config` secret. Parameters marked with [R]
are required.


##### Turbonomic API
  - **TR_HOST** - Turbonomic hostname or IP address: Default: `api.turbonomic.svc.cluster.local`

  - **TR_PORT** - Server port: Default `8080`

  - **TR_SSL** - Use SSL when connecting: Default: `False`

  - **TR_GROUPS** [R] - Comma separated list of groups to query

  - **TR_TAGS** [R] - Comma separated list of tags to use for email recipient

  - **TR_ACTION_TYPES** [R] - Comma separated list of Turbonomic action types such as SCALE or RESIZE

##### SMTP Settings
  - **TR_SMTP_HOST** [R] - SMTP hostname or IP address

  - **TR_SMTP_PORT** - SMTP port number: Default: `25`

  - **TR_SMTP_TLS** - Use TLS when connecting: Default: `False`

  - **TR_SMTP_AUTH** - SMTP auth string


##### Email Message Settings
  - **EMAIL_GROUP_MESSAGES** - Collate messages to the same destination address. Default: `True`

  - **TR_EMAIL_HTML** - Send messages as HTML: Default: `True`

  - **TR_EMAIL_SUBJECT** - Email subject for single message, regardless of grouping

  - **TR_EMAIL_SUBJECT_MULTI** - Alternate subject to use when grouping more than one message

  - **TR_EMAIL_BODY** - Individual message body (these are grouped by `EMAIL_GROUP_MESSAGES`)

  - **TR_EMAIL_TO** - Default email recipient

  - **TR_EMAIL_FROM** [R] - Email sender address

  - **TR_EMAIL_CC** - List of addresses to CC

  - **TR_EMAIL_BCC** - List of addresses to BCC

  - **TR_DATE** - Date format for `{DATE}` values. Default: `%Y-%m-%d`

  - **TR_TIME** - Time format for `{TIME}` values. Default: `%H:%M:%S`

  - **TR_TIMESTAMP** - Timestamp format for `{TIMESTAMP}` values. Default: `%Y-%m-%d %H:%M:%S`

##### Debugging Settings
  - **TR_DISABLE_SSL_WARN** - Disable SSL warnings. Default: `True`

  - **TR_HTTP_DEBUG** - Enable HTTP debugging. Default: `False`

  - **TR_EMAIL_DISABLE_SEND** - Disable sending emails, but still generate them. Default: `False`

  - **TR_EMAIL_TEST_OVERRIDE** - Send all email messages to this address for testing.


#### Update and deploy cron

The cronjob must be set to the desired interval required using standard cron
symbols. A default value has been set for 5:00 am every Saturday, based on the
local Kubernetes system time. A useful tool for cron syntax is https://cron.help/.

```
* : Expands to all values for the field
, : List separator
- : Range separator
/ : Specifies step for ranges

┌───────────── minute (0 - 59)
│ ┌───────────── hour (0 - 23)
│ │ ┌───────────── day of the month (1 - 31)
│ │ │ ┌───────────── month (1 - 12)
│ │ │ │ ┌───────────── day of the week (0 - 6) (Sunday to Saturday)
│ │ │ │ │
* 5 * * 6
```

After updating the desired cron interval, the configuration must be loaded.
Updates to the configuration are reloaded in the same manner as well.

```bash
kubectl apply -f cron.yaml
```

******


### Uninstallation <a name="uninstallation"></a>

Uninstallation with the `deploy.sh` script is accomplished with the `--uninstall`
flag. This will remove the image, secrets, and cron. This will not remove the
namespace, which may be in use by other containers, nor will it remove any
jobs that were created manually based on the cron.

```bash
./deploy.sh --uninstall
```

Manual uninstallation follows the reverse of the manual installation.

```bash
kubectl delete secrets -l app="tr-action-notification" -n "turbointegrations"
kubectl delete cronjob -l app="tr-action-notification" -n "turbointegrations"
```

The process of removing the container images from the local cache will differ based
on which container runtime you are using. If using dockershim, the process is as
follows:
```bash
sudo docker images | grep "tr-action-notification" | awk '{print $3}' | uniq | xargs sudo docker image rm -f
```

Note: Manually created jobs must be cleared by the user.