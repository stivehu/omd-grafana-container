# docker-omd-grafana
OMD Labs Edition with Grafana, InfluxDB, Nagflux and Histou configured (Debian 12 Bookworm)

## Build & Run
Creates an image with the latest OMD Labs Edition:
``` bash
$ git clone https://github.com/stivehu/omd-grafana-container.git
$ cd omd-grafana-container
$ docker build -t stivehu/omd-grafana .
$ docker run -it --rm -p 80:80 -p 443:443 -p 8086:8086 -h omd stivehu/omd-grafana
```
## Run
If not built manually, the latest version from hub.docker.com can be used: https://hub.docker.com/r/stivehu/omd-grafana/


### docker compose
``` yaml
services:
  omd-grafana:
    image: stivehu/omd-grafana
    hostname: omd
    ports:
      - "80:80"
      - "443:443"
      - "8086:8086"
    stdin_open: true
    tty: true
```
``` bash
$ docker compose up
```

```
browser: 127.0.0.1/default [windows: https://docs.docker.com/engine/installation/windows/#container-port-redirection]
user: omdadmin
pass: omd
It takes a few seconds until the first performance data is created.
```
