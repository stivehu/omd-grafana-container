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

    # Inject _GRAFANA_DASHBOARD=vm-performance default into the generic-service Naemon
    # template so services without an explicit override get the VM Performance dashboard.
    # SNMP traffic services should set _GRAFANA_DASHBOARD = snmp-interface in their config.
    NAEMON_CONF_D=/omd/sites/default/etc/naemon/conf.d
    GENERIC_CFG=$(grep -rl 'name[[:space:]]*generic-service' "$NAEMON_CONF_D" 2>/dev/null | head -1)
    if [ -n "$GENERIC_CFG" ] && ! grep -q '_GRAFANA_DASHBOARD' "$GENERIC_CFG"; then
        sed -i '/name[[:space:]]*generic-service/a\    _GRAFANA_DASHBOARD    vm-performance' "$GENERIC_CFG"
    fi

    # Configure Thruk to link performance graphs to the Grafana dashboard specified
    # by the _GRAFANA_DASHBOARD custom variable on each service.
    # Custom variable macro: _GRAFANA_DASHBOARD → $HOSTNAME$ / $SERVICEDESC$ in Thruk.
    THRUK_LOCAL=/omd/sites/default/etc/thruk/thruk_local.conf
    if [ -f "$THRUK_LOCAL" ] && ! grep -q '_SERVICEGRAFANA_DASHBOARD' "$THRUK_LOCAL"; then
        cat >> "$THRUK_LOCAL" <<'EOF'

# Performance graph links use the _GRAFANA_DASHBOARD custom variable on each service.
# Default (via generic-service template): vm-performance
# SNMP traffic services: set _GRAFANA_DASHBOARD = snmp-interface
pnp_url = /default/grafana/d/$_SERVICEGRAFANA_DASHBOARD$/$_SERVICEGRAFANA_DASHBOARD$?orgId=1&var-hostname=$HOSTNAME$&var-service=$SERVICEDESC$
EOF
    fi
else
    omd config default set PNP4NAGIOS on
fi

# The baked-in nagflux.d/nagflux-commands.cfg is only a fallback for a mounted
# conf.d that lacks histou.cfg. When conf.d already defines these commands
# (stock OMD 5.80+ histou.cfg), drop the fallback or Naemon refuses the
# duplicate definitions and does not start.
NAGFLUX_FALLBACK=/omd/sites/default/etc/naemon/nagflux.d/nagflux-commands.cfg
if grep -rqs --include='*.cfg' 'command_name[[:space:]]*omd-process-service-perfdata-file-nagflux' /omd/sites/default/etc/naemon/conf.d; then
    [ -f "$NAGFLUX_FALLBACK" ] && mv "$NAGFLUX_FALLBACK" "$NAGFLUX_FALLBACK.disabled"
elif [ -f "$NAGFLUX_FALLBACK.disabled" ]; then
    mv "$NAGFLUX_FALLBACK.disabled" "$NAGFLUX_FALLBACK"
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

# Apply a custom omdadmin password from PASSWORD (set via .env / --env-file),
# if given. Must run after "omd start" above, once the site is fully up -
# setting it earlier risks the site's own htpasswd being (re)written over it
# during startup.
if [ -n "${PASSWORD}" ]; then
    HTPASSWD_FILE=/omd/sites/default/etc/htpasswd
    htpasswd -b -m "$HTPASSWD_FILE" omdadmin "${PASSWORD}"
    chown default:default "$HTPASSWD_FILE"
    chmod 664 "$HTPASSWD_FILE"
fi


# Regenerate the classic status.dat that nagmapReborn reads, from Livestatus,
# every 10s (Naemon's own status_file writer is a no-op - see
# nagmap-status-bridge.py for why).
(
    while true; do
        python3 /usr/local/bin/nagmap-status-bridge.py
        sleep 10
    done
) &

omd status
tail -f /dev/null
