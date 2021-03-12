FROM turbointegrations/base:1.1.24-alpine

RUN apk --no-cache update \
    && apk --no-cache add bash curl jq \
    && mkdir -p /opt/turbonomic \
    && mkfifo /var/log/stdout \
    && chmod 0666 /var/log/stdout \
    && rm -rf /var/cache/apk/* \
    && rm -rf /tmp/*

COPY report.py /opt/turbonomic/report.py

SHELL ["/bin/bash", "-c"]

ENTRYPOINT ["python", "/opt/turbonomic/report.py"]
