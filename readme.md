# Proxmox Virtual Environment mods and scripts

A small collection of scripts and mods for Proxmox Virtual Environment (PVE).

If you find this helpful, a small donation is appreciated, [![Donate](https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=K8XPMSEBERH3W).

## Node sensor readings view

(Tested compatibility: 9.x. Using older version (7.x-8.x), use git version from Apr 6th 2025)
![Promxox temp mod](https://github.com/Meliox/PVE-mods/blob/main/pve-mod-sensors.png?raw=true)

This bash script installs a modification to the Proxmox Virtual Environment (PVE) web user interface (UI) to display sensor readings in a flexible and readable manner.

The following readings are possible:
- CPU, NVMe/HDD/SSD temperatures (Celsius/Fahrenheit), fan speeds, ram temperatures via lm-sensors. Note: Hdds require kernel module *drivetemp* module installed.
- UPS information via Network Monitoring Tool
- Motherboard information or system information via dmidecode

### How it works
The modification involves the following steps:
1. Backup original files in the home directory/backup
   - `/usr/share/pve-manager/js/pvemanagerlib.js`
   - `/usr/share/perl5/PVE/API2/Nodes.pm`
2. Patch `Nodes.pm` to enable readings.  
3. Modify `pvemanagerlib.js` to:  
   - Expand the node status view to full browser width.  
   - Add reading (depending on  & selections).  
   - Allow collapsing the panel vertically.  
4. Restart the `pveproxy` service to apply changes.

The script provides three options:

| **Option**             | **Description**                                                             |
|-------------------------|-----------------------------------------------------------------------------|
| `install`              | Apply the modification.                |
| `uninstall`            | Restore original files from backups.      |
| `save-sensors-data`    | Save a local copy of detected sensor data for reference or troubleshooting.             |

Notes:

- UPS support in multi-node setups require identical login credentials across nodes. This has not been fully tested.  
- Proxmox upgrades may overwrite modified files; reinstallation of this mod could be required.  

### Install (single node)

Instructions be performed as 'root', as normal users do not have access to the files.

```bash
apt-get install lm-sensors
# lm-sensors must be configured, run below to configure your sensors, apply temperature offsets. Refer to lm-sensors manual for more information.
sensors-detect 
wget https://raw.githubusercontent.com/DrDKuiper/PVE-mods/refs/heads/main/pve-mod-gui-sensors.sh
chmod +x pve-mod-gui-sensors.sh
bash pve-mod-gui-sensors.sh install
# Then clear the browser cache to ensure all changes are visualized.
```

#### UPS support (including APC/APCCTRL and Brazilian models)

To display UPS information in the GUI, the script relies on **Network UPS Tools (NUT)** and the `upsc` command (`nut-client` package). This supports a wide range of UPS devices, including APC models commonly vendidos no Brasil (drivers como `usbhid-ups`, `apcsmart`, `apcctrl`, etc.).

Basic steps:

1. Configure your UPS in `/etc/nut/ups.conf` on the NUT server (which can be the PVE host itself or another machine).
2. Test your UPS connection:

   ```bash
   upsc ups@localhost
   # or, for a named UPS and remote host
   upsc apc@192.168.1.10
   ```

3. When running `pve-mod-gui-sensors.sh`, answer **Yes** to enabling UPS and inform the same connection string, for example:

   - `ups@localhost`
   - `apc@192.168.1.10`

The script will:

- Verificar se o pacote `nut-client` (comando `upsc`) está instalado e oferecer instalação automática se necessário.
- Conectar ao UPS informado e detectar `device.model`, exibindo o nome do modelo diretamente no painel do Proxmox.
Additionally, adjustments are available in the first part of the script, where paths can be edited, cpucore offset and display information.

## Nag screen deactivation

(Tested compatibility: 7.x - 8.3.5)
This bash script installs a modification to the Proxmox Virtual Environment (PVE) web user interface (UI) which deactivates the subscription nag screen.

The modification includes two main steps:

1. Create backups of the original files in the `backup` directory relative to the script location.
2. Modify code.

The script provides three options:

| **Option**             | **Description**                                                             |
|-------------------------|-----------------------------------------------------------------------------|
| `install`              | Installs the modification by applying the necessary changes.                |
| `uninstall`            | Removes the modification by restoring the original files from backups.      |

### Install

Instructions be performed as 'root', as normal users do not have access to the files.

```bash
wget https://raw.githubusercontent.com/DrDKuiper/PVE-mods/refs/heads/main/pve-mod-nag-screen.sh
chmod +x pve-mod-nag-screen.sh
bash pve-mod-nag-screen.sh install
```

## Script to update all containers

(Tested compatibility: 7.x - 8.3.5)

This script updates all running Proxmox containers, skipping specified excluded containers, and generates a separate log file for each container.
The script first updates the Proxmox host system, then iterates through each container, updates the container, and reboots it if necessary.
Each container's log file is stored in $log_path and the main script log file is named container-upgrade-main.log.

### Install

```bash
wget https://raw.githubusercontent.com/DrDKuiper/PVE-mods/refs/heads/main/updateallcontainers.sh
chmod +x updateallcontainers.sh
```
Or use git clone.
Can be added to cron for e.g. monthly update: ```0 6 1 * * /root/scripts/updateallcontainers.sh```

## Run all GUI mods at once

To apply or uninstall all GUI-related mods in one go, you can use `pve-mod-all.sh`:

```bash
wget https://raw.githubusercontent.com/DrDKuiper/PVE-mods/refs/heads/main/pve-mod-all.sh
chmod +x pve-mod-all.sh
# Install all mods
./pve-mod-all.sh install
# Uninstall all mods
./pve-mod-all.sh uninstall
```

Run as `root` on the PVE node.
