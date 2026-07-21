#!/bin/bash

if [ "${PERF_BACKEND}" = "victoriametrics" ]; then
    /usr/local/bin/victoria-metrics \
        -storageDataPath=/var/lib/victoriametrics \
        -retentionPeriod=12 \
        -httpListenAddr=:8428 \
        >> /var/log/victoriametrics.log 2>&1 &

    # Nagflux posts to {address}/write{arguments}, so address must end at
    # /api/v1/import/influx to produce the correct VM write endpoint.
    omd config default set PNP4NAGIOS off

    # Configure Thruk to link performance graphs to the Grafana/VM dashboard.
    # Macros: $HOST$ = hostname, $SERVICE$ = service description (empty for host checks).
    THRUK_LOCAL=/omd/sites/default/etc/thruk/thruk_local.conf
    if [ -f "$THRUK_LOCAL" ] && ! grep -q 'vm-performance' "$THRUK_LOCAL"; then
        cat >> "$THRUK_LOCAL" <<'EOF'

# Performance graph links point to VictoriaMetrics via Grafana
pnp_url = /default/grafana/d/vm-performance/vm-performance?orgId=1&var-hostname=$HOST$&var-service=$SERVICE$
EOF
    fi
else
    omd config default set PNP4NAGIOS on
fi

service apache2 restart
omd start

if [ "${PERF_BACKEND}" = "victoriametrics" ]; then
    # OMD regenerates config.gcfg on every start, so enable victoriametrics AFTER omd start.
    NAGFLUX_CONF=/omd/sites/default/etc/nagflux/config.gcfg
    if [ -f "$NAGFLUX_CONF" ]; then
        sed -i '/^\[InfluxDB "victoriametrics"\]/,/^\[/ { s/^\tEnabled = false$/\tEnabled = true/ }' "$NAGFLUX_CONF"
        omd reload default nagflux
    fi
fi

omd status
tail -f /dev/null
