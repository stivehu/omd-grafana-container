# OMD with Grafana

# Run:
# $ docker run -it --rm -p 80:80 -p 443:443 -h omd griesbacher/omd-grafana

# browser: 127.0.0.1/default [windows: https://docs.docker.com/engine/installation/windows/#container-port-redirection]
# user: omdadmin
# pass: omd
# It takes a few seconds till the first Performancedata is created.

FROM debian:13

LABEL maintainer="Gábor István, stive.hu@gmail.com"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y curl ca-certificates

RUN curl -fsS "https://labs.consol.de/repo/stable/monitoring-repo-consol-de-gpg-2026.asc" \
    -o /etc/apt/trusted.gpg.d/monitoring-repo-consol-de-gpg-2026.asc

RUN echo "deb [signed-by=/etc/apt/trusted.gpg.d/monitoring-repo-consol-de-gpg-2026.asc] http://labs.consol.de/repo/stable/debian trixie main" \
    > /etc/apt/sources.list.d/labs-consol-stable.list

RUN apt-get update && apt-get install -y omd-labs-edition net-tools iputils-ping bc locales \
    && sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen \
    && locale-gen

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# libssl1.1 compatibility for plugins compiled against OpenSSL 1.1 (Debian 8/9 era); trixie only ships OpenSSL 3
# (bullseye is EOL; its packages now live on archive.debian.org)
RUN echo "deb http://archive.debian.org/debian-security bullseye-security main" \
        > /etc/apt/sources.list.d/bullseye-security.list \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && apt-get install -y libssl1.1 \
    && rm /etc/apt/sources.list.d/bullseye-security.list \
    && apt-get update

# 1. Enable non-free repository and update
RUN sed -i 's/main/main non-free/g' /etc/apt/sources.list.d/debian.sources
RUN apt -y update

# 2. Install the downloader
RUN apt -y install snmp-mibs-downloader python3-nagiosplugin python3-retrying

RUN omd create default
RUN omd config default set TMPFS off
RUN omd config default set INFLUXDB on
RUN omd config default set NAGFLUX on
RUN omd config default set GRAFANA on
RUN omd config default set CORE naemon
RUN omd config default set PNP4NAGIOS off

# telnetlib was removed from the standard library in Python 3.13 (trixie), but
# local plugins (check_cts_sfp.py) still import it. Install the unchanged
# backport into the site's local Python path (no pip in the image).
ARG TELNETLIB_VERSION=3.13.0
RUN U=$(curl -fsS "https://pypi.org/pypi/standard-telnetlib/${TELNETLIB_VERSION}/json" \
        | python3 -c 'import json,sys; print([f["url"] for f in json.load(sys.stdin)["urls"] if f["filename"].endswith(".whl")][0])') \
    && curl -fsSL "$U" -o /tmp/telnetlib.whl \
    && python3 -m zipfile -e /tmp/telnetlib.whl /omd/sites/default/local/lib/python/ \
    && rm /tmp/telnetlib.whl \
    && chown -R default:default /omd/sites/default/local/lib/python

# Install nagmapReborn (network map dashboard)
RUN apt-get install -y --no-install-recommends git \
    && cd /omd/sites/default/var && git clone https://github.com/stivehu/nagmapReborn.git \
    && chown -R root:root /omd/sites/default/var/nagmapReborn \
    && chown default:default /omd/sites/default/var/nagmapReborn/cache \
    && apt-get purge -y git && apt-get autoremove -y
COPY var_nagmap.conf 00_nagmap_deny.conf /omd/sites/default/etc/apache/conf.d/

# nagmapReborn reads host/map data from a classic "nagios.cfg"-style file, and
# host status from a classic status.dat - neither of which Naemon produces on
# its own (status_file is a no-op; see nagmap-status-bridge.py). nagmap-hosts.cfg
# gives it an absolute-path entry point into the real Naemon object config, and
# nagmap-status-bridge.py regenerates status.dat from Livestatus periodically.
COPY nagmap-hosts.cfg /omd/sites/default/etc/naemon/nagmap-hosts.cfg
COPY nagmap-status-bridge.py /usr/local/bin/nagmap-status-bridge.py
RUN chmod +x /usr/local/bin/nagmap-status-bridge.py

# Install VictoriaMetrics server
# Latest releases: https://github.com/VictoriaMetrics/VictoriaMetrics/releases
ARG VM_VERSION=1.102.0
RUN curl -fsSL \
       "https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v${VM_VERSION}/victoria-metrics-linux-amd64-v${VM_VERSION}.tar.gz" \
       -o /tmp/victoria-metrics.tar.gz \
    && tar -xzf /tmp/victoria-metrics.tar.gz -C /usr/local/bin/ victoria-metrics-prod \
    && mv /usr/local/bin/victoria-metrics-prod /usr/local/bin/victoria-metrics \
    && rm /tmp/victoria-metrics.tar.gz \
    && mkdir -p /var/lib/victoriametrics

# Install VictoriaMetrics Grafana datasource plugin
# Override VM_DS_VERSION at build time if a newer release is available:
#   docker build --build-arg VM_DS_VERSION=x.y.z ...
# Latest releases: https://github.com/VictoriaMetrics/victoriametrics-datasource/releases
ARG VM_DS_VERSION=0.11.0
RUN apt-get install -y --no-install-recommends unzip \
    && curl -fsSL \
       "https://github.com/VictoriaMetrics/victoriametrics-datasource/releases/download/v${VM_DS_VERSION}/victoriametrics-datasource-v${VM_DS_VERSION}.zip" \
       -o /tmp/vm-datasource.zip \
    && unzip /tmp/vm-datasource.zip -d /omd/sites/default/var/grafana/plugins/ \
    && rm /tmp/vm-datasource.zip \
    && chown -R default:default /omd/sites/default/var/grafana/plugins/ \
    && find /omd/sites/default/etc -name 'grafana.ini' -exec \
       sh -c 'printf "\n[plugins]\nallow_loading_unsigned_plugins = victoriametrics-datasource\n" >> "$1"' _ {} \;

# Bake nagflux perfdata processing commands into a separate cfg_dir so they
# survive a user-mounted conf.d that does not include histou.cfg.
RUN mkdir -p /omd/sites/default/etc/naemon/nagflux.d \
    && echo 'cfg_dir=etc/naemon/nagflux.d' \
       >> /omd/sites/default/etc/naemon/naemon.d/000_omd.cfg
COPY nagflux-commands.cfg /omd/sites/default/etc/naemon/nagflux.d/nagflux-commands.cfg
RUN chown -R default:default /omd/sites/default/etc/naemon/nagflux.d

# Provision VictoriaMetrics datasource and performance dashboard into Grafana
COPY grafana-provisioning/datasources/victoriametrics.yaml \
     /omd/sites/default/etc/grafana/provisioning/datasources/victoriametrics.yaml
COPY grafana-provisioning/dashboards/dashboards.yaml \
     /omd/sites/default/etc/grafana/provisioning/dashboards/vm-dashboards.yaml
RUN mkdir -p /omd/sites/default/var/grafana/dashboards/provisioned
COPY grafana-dashboards/vm-performance.json \
     /omd/sites/default/var/grafana/dashboards/provisioned/vm-performance.json
COPY grafana-dashboards/snmp-interface.json \
     /omd/sites/default/var/grafana/dashboards/provisioned/snmp-interface.json
RUN chown -R default:default \
        /omd/sites/default/etc/grafana/provisioning/ \
        /omd/sites/default/var/grafana/dashboards/

ENV PERF_BACKEND=victoriametrics

EXPOSE 80 443 8086 8428

COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
RUN sed -i 's/\r//' /entrypoint.sh #Just for Windowssystems...

ENTRYPOINT ["/entrypoint.sh"]
