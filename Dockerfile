# OMD with Grafana

# Run:
# $ docker run -it --rm -p 80:80 -p 443:443 -h omd griesbacher/omd-grafana

# browser: 127.0.0.1/default [windows: https://docs.docker.com/engine/installation/windows/#container-port-redirection]
# user: omdadmin
# pass: omd
# It takes a few seconds till the first Performancedata is created.

FROM debian:12

LABEL maintainer="Philip Griesbacher, philip.griesbacher@consol.de"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y curl ca-certificates

RUN curl -fsS "https://labs.consol.de/repo/stable/monitoring-repo-consol-de-gpg-2026.asc" \
    -o /etc/apt/trusted.gpg.d/monitoring-repo-consol-de-gpg-2026.asc

RUN echo "deb [signed-by=/etc/apt/trusted.gpg.d/monitoring-repo-consol-de-gpg-2026.asc] http://labs.consol.de/repo/stable/debian bookworm main" \
    > /etc/apt/sources.list.d/labs-consol-stable.list

RUN apt-get update && apt-get install -y omd-labs-edition net-tools iputils-ping bc

# libssl1.1 compatibility for plugins compiled against OpenSSL 1.1 (Debian 8/9 era)
RUN echo "deb http://security.debian.org/debian-security bullseye-security main" \
        > /etc/apt/sources.list.d/bullseye-security.list \
    && apt-get update \
    && apt-get install -y libssl1.1 \
    && rm /etc/apt/sources.list.d/bullseye-security.list \
    && apt-get update

# 1. Enable non-free repository and update
RUN sed -i 's/main/main non-free/g' /etc/apt/sources.list.d/debian.sources
RUN apt -y update

# 2. Install the downloader
RUN apt -y install snmp-mibs-downloader

RUN omd create default
RUN omd config default set TMPFS off
RUN omd config default set INFLUXDB on
RUN omd config default set NAGFLUX on
RUN omd config default set GRAFANA on
RUN omd config default set CORE naemon
RUN omd config default set PNP4NAGIOS off

EXPOSE 80 443 8086

COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
RUN sed -i 's/\r//' /entrypoint.sh #Just for Windowssystems...

ENTRYPOINT ["/entrypoint.sh"]
