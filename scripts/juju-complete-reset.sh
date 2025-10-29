#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║     JUJU COMPLETE RESET - One-Shot Bootstrap             ║"
echo "╚════════════════════════════════════════════════════════════╝"

sudo pkill -9 jujud juju mongod 2>/dev/null || true
sleep 2

sudo snap remove juju --purge juju-db --purge 2>/dev/null || true
sleep 5

sudo rm -rf /var/lib/juju /var/run/juju /var/cache/juju /var/snap/juju* 2>/dev/null || true
rm -rf ~/.local/share/juju ~/.juju ~/.cache/juju 2>/dev/null || true

sudo snap install juju --classic
sleep 10

cd ~
/snap/bin/juju bootstrap manual/serpro@10.35.0.9 ha-controller --constraints "mem=4G cores=2" --config enable-os-refresh-update=false --config enable-os-upgrade=true
sleep 120
/snap/bin/juju add-model default
sleep 20
/snap/bin/juju status
echo "✓ COMPLETE"
