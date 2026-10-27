# GRE Tunnel Manager

A small interactive Bash script for managing GRE tunnels on Ubuntu/Debian servers.

## Features

- Asks for the remote server public IPv4.
- Asks for the GRE tunnel/interface name (max 15 characters).
- Lets you choose the current server side:
  - Iran = local inner IP `.1`, remote inner IP `.2`
  - Europe = local inner IP `.2`, remote inner IP `.1`
- Provides 10 predefined inner-IP pairs:
  - `10.20.20.1 <-> 10.20.20.2`
  - `10.21.20.1 <-> 10.21.20.2`
  - ...
  - `10.29.20.1 <-> 10.29.20.2`
- Option 11 deletes only the currently live tunnel.
- Option 12 makes the current live tunnel permanent with systemd so it returns after reboot.
- Option 13 completely removes the tunnel and any permanent systemd configuration.

## Run

```bash
chmod +x petex-gre-manager.sh
sudo ./petex-gre-manager.sh
```

Run the same script separately on both ends, using the opposite public IP and opposite side selection.

## Example

### Iran server

- Remote public IP: `100.70.250.10`
- Tunnel: `ge4`
- Side: `Iran`
- Pair: `10.24.20.1 <-> 10.24.20.2`

### Europe server

- Remote public IP: `81.82.83.4`
- Tunnel: `ge4`
- Side: `Europe`
- Pair: `10.24.20.1 <-> 10.24.20.2`

Then test from Iran:

```bash
ping -c 10 10.24.20.2
```

After you select the best working pair, run the script again and choose option 12 to make the current live tunnel persistent.
