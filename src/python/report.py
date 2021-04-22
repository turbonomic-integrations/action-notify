#! /usr/local/bin/python3

import base64
import copy
import datetime
from decimal import Decimal
from email.mime.multipart import MIMEMultipart
from email.utils import COMMASPACE, formatdate
from email.mime.text import MIMEText
from email.mime.application import MIMEApplication
import json
import logging
from logging import StreamHandler, FileHandler
import os
import re
import smtplib
import socket

import umsg
from umsg import _msg
import urllib3
import vmtconnect as vc



## ----------------------------------------------------
##  Global Definitions
## ----------------------------------------------------
# hard defaults
WORKING_DIR = os.environ.get('TR_WORKING_DIR', '/opt/turbonomic')
LOGGER = None
LOG_FORMATTER = logging.Formatter(
    fmt='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S')
LOG_FILE = os.environ.get('TR_LOG_FILE', '/var/log/stdout')
LOG_MODE = umsg.util.log_level(os.environ.get('TR_LOG_MODE', logging.DEBUG))
MSG_PREFIX = 'init'

HTTP_DEBUG = vc.util.str_to_bool(os.environ.get('TR_HTTP_DEBUG', 'False'))
DISABLE_SSL_WARNINGS = vc.util.str_to_bool(os.environ.get('TR_DISABLE_SSL_WARN', 'True'))
EMAIL_TEST_OVERRIDE = os.environ.get('TR_EMAIL_TEST_OVERRIDE')
EMAIL_DISABLE_SEND = vc.util.str_to_bool(os.environ.get('TR_EMAIL_DISABLE_SEND', 'False'))

FORMAT_DATE = os.environ.get('TR_DATE', '%Y-%m-%d')
FORMAT_TIME = os.environ.get('TR_TIME', '%H:%M:%S')
FORMAT_TIMESTAMP = os.environ.get('TR_TIMESTAMP', f"{FORMAT_DATE} {FORMAT_TIME}")

HOST = os.environ.get('TR_HOST', 'api.turbonomic.svc.cluster.local')
PORT = os.environ.get('TR_PORT', '8080')
AUTH = os.environ.get('TR_AUTH')
SSL = vc.util.str_to_bool(os.environ.get('TR_SSL', 'False'))

SMTP = {
    'host': os.environ.get('TR_SMTP_HOST'),
    'port': os.environ.get('TR_SMTP_PORT'),
    'tls': vc.util.str_to_bool(os.environ.get('TR_SMTP_TLS', 'False')),
    'auth': os.environ.get('TR_SMTP_AUTH')
}

ACTION_TYPES = os.environ.get('TR_ACTION_TYPES', 'SCALE').upper()
EMAIL_GROUP_MESSAGES = vc.util.str_to_bool(os.environ.get('TR_EMAIL_GROUP_MESSAGES', 'True'))

HTML = vc.util.str_to_bool(os.environ.get('TR_EMAIL_HTML', 'True'))
EMAIL_HTML_HEAD = '''
<!DOCTYPE html PUBLIC “-//W3C//DTD XHTML 1.0 Transitional//EN” “https://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd”>
<html xmlns=“https://www.w3.org/1999/xhtml”>
<head>
<title>{SUBJECT}</title>
<meta http–equiv=“Content-Type” content=“text/html; charset=UTF-8” />
<meta http–equiv=“X-UA-Compatible” content=“IE=edge” />
<meta name=“viewport” content=“width=device-width, initial-scale=1.0 “ />
<style>

</style>
</head>
<body>
'''
EMAIL_HTML_FOOT = '''
</body>
</html>
'''

EMAIL_TEMPLATE = {
    'subject': os.environ.get('TR_EMAIL_SUBJECT','Turbonomic Resize Action Generated for {WORKLOAD}'),
    'subject_multi': os.environ.get('TR_EMAIL_SUBJECT_MULTI','Turbonomic Resize Action Generated for {WORKLOAD} and {WORKLOAD_COUNT} others'),
    'body': os.environ.get('TR_EMAIL_BODY', 'Description: {DESCRIPTION}<br />\nReason: {REASON}<br />\nSavings: {SAVINGS}<br />\n'),
    'to': os.environ.get('TR_EMAIL_TO'),
    'from': os.environ.get('TR_EMAIL_FROM'),
    'cc': os.environ.get('TR_EMAIL_CC'),
    'bcc': os.environ.get('TR_EMAIL_BCC'),
    'send_as_html': HTML,
    'header': os.environ.get('TR_EMAIL_HEADER', EMAIL_HTML_HEAD if HTML else ''),
    'div': os.environ.get('TR_EMAIL_DIV', '<br /><hr><br />' if HTML else '='*25),
    'part_header': os.environ.get('TR_EMAIL_PART_HEADER', ''),
    'part_footer': os.environ.get('TR_EMAIL_PART_FOOTER', ''),
    'footer': os.environ.get('TR_EMAIL_FOOTER', EMAIL_HTML_FOOT if HTML else '')
}

GROUPS = os.environ.get('TR_GROUPS')
EMAIL_TAGS = os.environ.get('TR_TAGS')
HOURS_IN_MONTH = os.environ.get('TR_HOURS_IN_MONTH', 730)



## ----------------------------------------------------
##  Classes
## ----------------------------------------------------
class RequiredValueMissing(Exception):
    pass


class Mailer:
    def __init__(self, host=None, port=None, tls=False,
                 username=None, password=None):
        self._host = host if host else 'localhost'
        self._port = port if port else 25
        self._tls = tls
        self._user = username
        self._pass = password

    @staticmethod
    def format_addresses(addr):
        return COMMASPACE.join(addr) if isinstance(addr, list) else addr

    def send(self, subject, body, to_addr, from_addr, cc_addr=None,
             bcc_addr=None, html=False, attachments=None):
        msg = MIMEMultipart('mixed')
        msg['From'] = from_addr
        msg['Date'] = formatdate(localtime=True)
        msg['Subject'] = subject
        msg['To'] = self.format_addresses(to_addr)

        if cc_addr:
            msg['Cc'] = self.format_addresses(cc_addr)

        if bcc_addr:
            msg['Bcc'] = self.format_addresses(bcc_addr)

        msg.attach(MIMEText(body, 'html' if html else 'plain'))

        if attachments:
            for f in attachments:
                with open(f, 'rb') as fp:
                    part = MIMEApplication(fp.read(), Name=os.path.basename(f))

                part['Content-Disposition'] = (f"attachment; filename=\"{os.path.basename(f)}\"")
                msg.attach(part)

        with smtplib.SMTP(self._host, port=self._port) as smtp:
            if self._tls:
                smtp.starttls()
            if self._user and self._pass:
                smtp.login(self._user, self._pass)

            smtp.send_message(msg)

# end class definitions ==========================================


## ----------------------------------------------------
##  Functions
## ----------------------------------------------------
def required(name, value=None):
    if not value:
        raise RequiredValueMissing(f"Required value null or missing: {name}")


def split_trim(string, delim=','):
    return [x.strip() for x in string.split(delim)]


def parse_string(input, **kwargs):
    if input is not None and '{' in input:
        return input.format(
            date=datetime.date.today().strftime(FORMAT_DATE),
            time=datetime.datetime.now().strftime(FORMAT_TIME),
            timestamp=datetime.datetime.now().strftime(FORMAT_TIMESTAMP),
            **kwargs
        )
    else:
        return input


def validate_email(addr):
    pattern = r"(^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$)"
    return re.match(pattern, addr, re.IGNORECASE)


def init_log_handler(formatter, mode, file=None):
    if file:
        handler = FileHandler(file)
    else:
        handler = StreamHandler()

    handler.setFormatter(formatter)
    handler.setLevel(mode)

    return handler


def send_notification(email, smtp):
    prefix = 'send'

    if smtp.get('auth'):
        _user, _pass = base64.b64decode(smtp['auth']).decode().split(':', 1)
        mailer = Mailer(smtp['host'], smtp['port'], smtp['tls'], _user, _pass)
    else:
        mailer = Mailer(smtp['host'], smtp['port'], smtp['tls'])

    if not EMAIL_DISABLE_SEND:
        mailer.send(email['subject'],
                    email['body'],
                    email['to'],
                    email['from'],
                    email['cc'],
                    email['bcc'],
                    email['send_as_html']
                   )


def prepare_message(email_template, subject, body_values):
    header = parse_string(email_template['header'], SUBJECT=subject)
    part_header = email_template['part_header']
    part_footer = email_template['part_footer']
    footer = email_template['footer']
    div = email_template['div']
    html = email_template['send_as_html']
    body_format = email_template['body']
    body = ''

    if not isinstance(body_values, list):
        body_values = [body_values]

    multi = False

    for values in body_values:
        if multi:
            body += f"\n{div}\n"

        body += f"\n{part_header}\n{parse_string(body_format, **values)}\n{part_footer}\n"
        multi = True

    return f"{header}\n{body}\n{footer}\n"


def process_notifications(data, email_template, smtp_config):
    prefix = 'notify'
    msgcnt = 0
    errcnt = 0

    for to, details in data.items():
        _email = copy.deepcopy(email_template)
        _email['to'] = to
        _msg(f"Processing {to}", level='debug', prefix=prefix)

        if EMAIL_TEST_OVERRIDE:
            _email['to'] = EMAIL_TEST_OVERRIDE
            _msg(f"Email override: {EMAIL_TEST_OVERRIDE}", level='debug', prefix=prefix)

        try:
            if EMAIL_GROUP_MESSAGES:
                if len(details) > 1:
                    _email['subject'] = parse_string(email_template['subject_multi'],
                                                     WORKLOAD_COUNT=len(details)-1,
                                                     **details[0])
                else:
                    _email['subject'] = parse_string(email_template['subject'], **details[0])

                _email['body'] = prepare_message(email_template, _email['subject'], details)
                send_notification(_email, smtp_config)
                msgcnt += 1
            else:
                for _detail in details:
                    _email['subject'] = parse_string(email_template['subject'], **_detail)
                    _email['body'] = prepare_message(email_template, _email['subject'], _detail)
                    send_notification(_email, smtp_config)
                    msgcnt += 1

        except Exception as e:
            if errcnt < 3:
                errcnt += 1
                _msg(f"Email notification exception {e}", level='debug', prefix=prefix, exc_info=True)
                pass
            else:
                raise Exception('Too many mail exceptions')

    return msgcnt


def get_action_detail(action, tags, default_email):
    prefix = 'action'

    if 'stats' in action:
        for x in action['stats']:
            if x['name'] == 'costPrice' and x['units'] == '$/h':
                savings = str(round(Decimal(x['value']) * HOURS_IN_MONTH, 2))
    else:
        savings = '-'

    to = default_email
    values = {
        'DESCRIPTION': action['details'],
        'WORKLOAD': action['target']['displayName'],
        'REASON': action['risk'].get('description'),
        'SAVINGS':  f"${savings}/mo"
    }

    for t in tags:
        try:
            if validate_email(action['target']['tags'][t][0]):
                to = action['target']['tags'][t][0]
                break
        except (IndexError, KeyError, TypeError):
            continue

    if to == default_email:
        _msg(f"No email tag found, using default address: {to}", level='debug', prefix=prefix)

    _msg(f"To: {to}", prefix=prefix)
    _msg(f"Workload: {values['WORKLOAD']}", prefix=prefix)
    _msg(f"Description: {values['DESCRIPTION']}", prefix=prefix)
    _msg(f"Reason: {values['REASON']}", prefix=prefix)
    _msg(f"Savings: {values['SAVINGS']}", prefix=prefix)

    return (to, values)


def main():
    prefix = 'main'
    _host = f"{HOST}:{PORT}" if PORT else HOST
    notifications = {}
    tags = split_trim(EMAIL_TAGS)
    groups = split_trim(GROUPS)
    types = split_trim(ACTION_TYPES)
    vmtsess = vc.Connection(host=_host, auth=AUTH, ssl=SSL)

    for grp in groups:
        try:
            uuid = vmtsess.get_group_by_name(grp)[0]['uuid']
            _msg(f"Processing group [{uuid}]:[{grp}]", prefix=prefix)

            actions = vmtsess.get_group_actions(uuid, pager=True)
        except (IndexError, KeyError, TypeError):
            _msg(f"Error processing group [{grp}], name does not exist, skipping", prefix=prefix)
            continue

        while not actions.complete:
            for act in actions.next:
                act_prefix = act['uuid']

                if act['actionType'] not in types:
                    continue

                try:
                    to, details = get_action_detail(act, tags, EMAIL_TEMPLATE['to'])

                    if to not in notifications:
                        notifications[to] = []

                    notifications[to].append(details)

                except KeyError:
                    _msg(f"Skipping [{details['WORKLOAD']}, missing required value: {e}]", prefix=prefix)
                    continue

    ret = process_notifications(notifications, EMAIL_TEMPLATE, SMTP)
    _msg(f"{ret} notifications sent", prefix=prefix)


## ----------------------------------------------------
##  python __main__ execution
## ----------------------------------------------------
if __name__ == '__main__':
    try:
        required('TR_ACTION_TYPES', ACTION_TYPES)
        required('TR_AUTH', AUTH)
        required('TR_GROUPS', GROUPS)
        required('TR_TAGS', EMAIL_TAGS)

        os.chdir(WORKING_DIR)
        socket.setdefaulttimeout(30)

        vmt_handler = init_log_handler(LOG_FORMATTER, LOG_MODE)
        umsg.init(mode=LOG_MODE, msg_prefix=MSG_PREFIX)
        umsg.add_handler(vmt_handler)
        LOGGER = umsg.get_attr('logger')
        LOGGER.setLevel(LOG_MODE)

        if DISABLE_SSL_WARNINGS:
            _msg('Disabling SSL warnings', level='debug')
            urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

        if HTTP_DEBUG:
            _msg('HTTP Debuging output enabled', level='debug')
            from http.client import HTTPConnection
            HTTPConnection.debuglevel = 1
            requests_log = logging.getLogger('requests.packages.urllib3')
            requests_log.setLevel(logging.DEBUG)
            requests_log.propagate = True

        main()
        exit(0)

    except ImportError as e:
        _msg(f"Initialization failure: {e}", level='error', dual=True)
    except (vc.VMTConnectionError, ConnectionError) as e:
        _msg(str(e), level='error')
    except Exception as e:
        _msg(f"Fatal exception: {str(e)}", level='error', exc_info=True)

    exit(1)
