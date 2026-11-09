# 100 GbE direct link (c4140 <-> c4140-2) — permanent addressing

Direct ConnectX-5 <-> ConnectX-4 link, own /30, **no gateway and no DNS** (internet traffic keeps using the 1 GbE port).

c4140 (Ubuntu, systemd-networkd) — `/etc/netplan/60-100g-link.yaml`, chmod 600, then `netplan generate && networkctl reload && networkctl reconfigure <iface>`:

```yaml
network:
  version: 2
  ethernets:
    enp94s0np0:
      dhcp4: false
      dhcp6: false
      accept-ra: false
      link-local: []
      addresses: [10.77.77.1/30]
      mtu: 9000
```

c4140-2 (Linux Mint, NetworkManager):

```bash
sudo nmcli con add type ethernet con-name 100g-link ifname enp94s0f0np0 connection.autoconnect yes \
  connection.autoconnect-priority 100 ipv4.method manual ipv4.addresses 10.77.77.2/30 ipv4.never-default yes \
  ipv6.method disabled 802-3-ethernet.mtu 9000
sudo nmcli con up 100g-link
```

Without a profile NetworkManager runs DHCP on the port and removes hand-set addresses (an earlier automated test broke exactly that way).

Checks: `ping -M do -s 8972 10.77.77.2` (jumbo frames), `iperf3 -P 8`, `ib_write_bw -d mlx5_0 -x 3 -F --report_gbits 10.77.77.2` (RoCE v2 GID index 3).
