# docker-omd-grafana

OMD Labs Edition with Grafana, InfluxDB, VictoriaMetrics, Nagflux configured on Debian 12 (Bookworm).

**Data flow (victoriametrics mode):**
```
Naemon (checks) → Nagflux → InfluxDB (port 8086)      → Grafana
                           ↘ VictoriaMetrics (port 8428) → Grafana
```

## Build & Run

```bash
git clone https://github.com/stivehu/omd-grafana-container.git
cd omd-grafana-container
docker build -t stivehu/omd-grafana .
docker run -it --rm -p 80:80 -p 443:443 -p 8086:8086 -p 8428:8428 -h omd stivehu/omd-grafana
```

- Thruk web UI: `http://127.0.0.1/default` — user: `omdadmin`, pass: `omd`
- Grafana: `http://127.0.0.1/default/grafana`

### docker compose

```yaml
services:
  omd-grafana:
    image: stivehu/omd-grafana
    hostname: omd
    ports:
      - "80:80"
      - "443:443"
      - "8086:8086"
      - "8428:8428"
    stdin_open: true
    tty: true
    environment:
      - PERF_BACKEND=victoriametrics   # or: rrd
    volumes:
      - ./victoriametrics-data/:/var/lib/victoriametrics/
      - ./conf.d/:/omd/sites/default/etc/naemon/conf.d/
```

```bash
docker compose up -d
```

> **Note on `conf.d` volume mount:** Mounting `./conf.d/` replaces the image's built-in `conf.d` entirely — place your host, service, and command definitions there. The nagflux perfdata processing commands (`omd-process-*-perfdata-file-nagflux`) are baked into a separate `nagflux.d` directory inside the image and are not affected by this mount.

## Performance backend

The backend for storing and displaying performance graphs is selectable via the `PERF_BACKEND` environment variable:

| Value | Backend | Notes |
|-------|---------|-------|
| `victoriametrics` (default) | VictoriaMetrics + Grafana (`vm-performance` dashboard) | Nagflux sends data to both InfluxDB (8086) and VictoriaMetrics (8428) |
| `rrd` | PNP4Nagios + RRD files | Nagflux sends data to InfluxDB (8086) only; VictoriaMetrics disabled |

When using `victoriametrics`:
- VictoriaMetrics starts on port 8428
- Nagflux forwards Naemon performance data to VictoriaMetrics
- The VictoriaMetrics datasource and a `vm-performance` dashboard are auto-provisioned in Grafana
- Host/service extinfo pages in Thruk link directly to the Grafana dashboard

## Pre-built image

The latest image is available on Docker Hub: https://hub.docker.com/r/stivehu/omd-grafana/
