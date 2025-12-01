#!/usr/bin/env bash
set -euo pipefail

# pve-mod-install-apcctrl.sh
# Automated installer for APCCTRL integration with PVE Mods
# - Inserts a safe APCCTRL parsing block into /usr/share/perl5/PVE/API2/Nodes.pm
# - Creates an exporter service/timer to write /var/lib/pve-mods/apcctrl-status.json
# - Validates Perl syntax and restarts pveproxy

APC_JSON="/var/lib/pve-mods/apcctrl-status.json"
NODES_FILE="/usr/share/perl5/PVE/API2/Nodes.pm"
BACKUP_DIR="/root"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root: sudo bash $0"
  exit 1
fi

echo "Creating /var/lib/pve-mods if missing"
mkdir -p /var/lib/pve-mods
chown root:root /var/lib/pve-mods
chmod 0755 /var/lib/pve-mods

if [ ! -f "$NODES_FILE" ]; then
  echo "Error: $NODES_FILE not found on this system. Aborting." >&2
  exit 1
fi

TS=$(date +%s)
BACKUP="$BACKUP_DIR/Nodes.pm.pve-mods.bak.$TS"
cp -a "$NODES_FILE" "$BACKUP"
echo "Backed up $NODES_FILE -> $BACKUP"

# Create temporary snippet file
SNIP=$(mktemp)
cat > "$SNIP" <<'PERL_SNIP'
# --- BEGIN pve-mods APCCTRL exporter parsing (added by pve-mods) ---
my $apc_file = '/var/lib/pve-mods/apcctrl-status.json';
if (-e $apc_file) {
    my $content = eval {
        local $/ = undef;
        open my $fh, '<', $apc_file or return undef;
        my $c = <$fh>;
        close $fh;
        $c;
    };

    if (defined $content && $content =~ /\S/) {
        my %vals;
        for my $line (split /\n/, $content) {
            next unless $line =~ /^\s*([A-Z0-9]+)\s*:\s*(.+)$/;
            my ($k, $v) = (lc $1, $2);
            $v =~ s/\s*Volts$//i;
            $v =~ s/\s*Percent$//i;
            $v =~ s/\s*Minutes$//i;
            $v =~ s/\s*Seconds$//i;
            $v =~ s/\s*$//;
            $v =~ s/^\s*//;
            $vals{$k} = $v;
        }

        my $upsc = {};
        $upsc->{model}     = $vals{model}    // '';
        $upsc->{status}    = $vals{status}   // '';
        $upsc->{linev}     = $vals{linev} + 0      if defined $vals{linev};
        $upsc->{bcharge}   = $vals{bcharge} + 0    if defined $vals{bcharge};
        if (defined $vals{timeleft}) {
            $upsc->{timeleft} = int($vals{timeleft} * 60); # minutes -> seconds
        }
        $upsc->{loadpct}   = $vals{loadpct} + 0    if defined $vals{loadpct};
        $upsc->{outputv}   = $vals{outputv} + 0    if defined $vals{outputv};
        $upsc->{linefreq}  = $vals{linefreq} + 0   if defined $vals{linefreq};
        $upsc->{battv}     = $vals{battv} + 0      if defined $vals{battv};
        $upsc->{mbattchg}  = $vals{mbattchg}       if defined $vals{mbattchg};
        $upsc->{mintimel}  = $vals{mintimel}       if defined $vals{mintimel};
        $upsc->{nompower}  = $vals{nompower} + 0    if defined $vals{nompower};

        $res->{upsc} = $upsc;
    }
}
# --- END pve-mods APCCTRL exporter parsing ---
PERL_SNIP

echo "Inserting APCCTRL snippet into $NODES_FILE"

# Insert snippet before the first 'return $res;' after the rootfs block
awk -v snipfile="$SNIP" '
  BEGIN { inserted = 0; rootfs_seen = 0; while ((getline line < snipfile) > 0) { snip = snip line "\n" } close(snipfile) }
  {
    print $0
    if ($0 ~ /\$res\s*->\{rootfs\}/) { rootfs_seen = 1 }
    if (rootfs_seen && $0 ~ /^\s*return\s+\$res\s*;\s*$/ && !inserted) {
      print snip
      inserted = 1
    }
  }
' "$NODES_FILE" > "${NODES_FILE}.new"

if ! grep -q "BEGIN pve-mods APCCTRL exporter parsing" "${NODES_FILE}.new"; then
  echo "Insertion marker not found in new file — aborting and restoring backup" >&2
  rm -f "${NODES_FILE}.new" "$SNIP"
  mv "$BACKUP" "$NODES_FILE"
  exit 1
fi

mv "${NODES_FILE}.new" "$NODES_FILE"
rm -f "$SNIP"
echo "Snippet inserted into $NODES_FILE"

echo "Checking Perl syntax for $NODES_FILE"
if perl -c "$NODES_FILE"; then
  echo "Perl syntax OK"
else
  echo "Perl syntax failed — restoring backup and aborting" >&2
  mv "$BACKUP" "$NODES_FILE"
  exit 1
fi

echo
echo "Creating systemd exporter unit and timer for apcaccess -> $APC_JSON (if missing)"

EXPORT_SERVICE="/etc/systemd/system/apcctrl-status.service"
EXPORT_TIMER="/etc/systemd/system/apcctrl-status.timer"

if [ ! -f "$EXPORT_SERVICE" ]; then
  cat > "$EXPORT_SERVICE" <<'SERVICE'
[Unit]
Description=APCCTRL status exporter (one-shot)
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c '/usr/bin/apcaccess status > /var/lib/pve-mods/apcctrl-status.json 2>&1 || true'
Nice=10
SERVICE
  echo "Created $EXPORT_SERVICE"
else
  echo "$EXPORT_SERVICE already exists; skipping"
fi

if [ ! -f "$EXPORT_TIMER" ]; then
  cat > "$EXPORT_TIMER" <<'TIMER'
[Unit]
Description=Run apcctrl-status exporter every 15s

[Timer]
OnUnitActiveSec=15
AccuracySec=1s
Unit=apcctrl-status.service

[Install]
WantedBy=timers.target
TIMER
  echo "Created $EXPORT_TIMER"
else
  echo "$EXPORT_TIMER already exists; skipping"
fi

systemctl daemon-reload
systemctl enable --now apcctrl-status.timer || true
echo "Enabled and started apcctrl-status.timer (writes $APC_JSON)"

echo
echo "Triggering one immediate export to populate $APC_JSON"
systemctl start apcctrl-status.service || true
sleep 1
if [ -s "$APC_JSON" ]; then
  echo "$APC_JSON created and non-empty"
else
  echo "Warning: $APC_JSON is missing or empty. Run 'apcaccess status' manually to debug." >&2
fi

echo
echo "Restarting pveproxy so API picks up new Nodes.pm"
systemctl restart pveproxy
echo "pveproxy restarted"

echo
echo "Done. Verify with:"
echo "  perl -c $NODES_FILE"
echo "  pvesh get /nodes/$(hostname)/status | python3 -m json.tool | sed -n '1,200p' | sed -n '/\"upsc\"/,/}/p'"
echo
echo "If the 'upsc' block appears, refresh browser and clear cache to see GUI widget." 

exit 0
