#!/usr/bin/env python3
"""Find a paired Automate listener on the current, explicitly allowed home LAN."""
import concurrent.futures
import hashlib
import hmac
import ipaddress
import json
from pathlib import Path
import secrets
import subprocess
import sys
import urllib.request


def command(*args):
    return subprocess.check_output(args, text=True, timeout=2, stderr=subprocess.DEVNULL)


def home_network(config):
    """Require a saved connection UUID and a configured IPv4 subnet on that device."""
    active = command('nmcli', '-t', '-f', 'UUID,TYPE,DEVICE', 'connection', 'show', '--active')
    for line in active.splitlines():
        uuid, kind, device = line.split(':', 2)
        if kind != '802-11-wireless':
            continue
        for home in config['homeNetworks']:
            if home['uuid'] != uuid:
                continue
            subnet = ipaddress.ip_network(home['cidr'])
            if not subnet.is_private or subnet.version != 4 or subnet.num_addresses > 256:
                raise ValueError('Home subnet must be a private IPv4 /24 or smaller')
            addresses = json.loads(command('ip', '-j', '-4', 'address', 'show', 'dev', device))
            own = {a['local'] for d in addresses for a in d['addr_info'] if a['family'] == 'inet'}
            if any(ipaddress.ip_address(a) in subnet for a in own):
                return device, subnet, own
    return None


class LocalProbeRedirects(urllib.request.HTTPRedirectHandler):
    """Keep a candidate probe on its original address and port."""
    def redirect_request(self, request, response, code, message, headers, new_url):
        return None


def verify(address, config, timeout=.65):
    """Send only a public challenge until the listener proves its paired identity."""
    nonce = secrets.token_hex(32)
    body = json.dumps({'op': 'probe', 'nonce': nonce}).encode()
    request = urllib.request.Request(f"http://{address}:{config['port']}/qs-alarm", data=body,
                                     headers={'Content-Type': 'application/json'})
    try:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), LocalProbeRedirects())
        with opener.open(request, timeout=timeout) as reply:
            data = json.loads(reply.read(4097))
        proof = hashlib.sha256((config['secret'] + ':' + nonce).encode()).hexdigest()
        return data.get('v') == 1 and data.get('pairId') == config['pairId'] and data.get('nonce') == nonce and hmac.compare_digest(data.get('proof', ''), proof)
    except (OSError, ValueError, TypeError):
        return False


def discover(config, cached=''):
    network = home_network(config)
    if network is None:
        return {'home': False, 'address': ''}
    device, subnet, own = network
    candidates = []
    def add(address):
        try:
            ip = ipaddress.ip_address(address)
            if ip in subnet and str(ip) not in own and str(ip) not in candidates:
                candidates.append(str(ip))
        except ValueError:
            pass
    add(cached)
    add(config.get('address', ''))
    priority_count = len(candidates)
    # A hostname and neighbour entry are hints; neither establishes identity.
    hostname = config.get('hostname', '')
    if hostname and hostname.endswith('.local') and len(hostname) <= 253:
        try:
            for line in command('getent', 'ahostsv4', hostname).splitlines():
                add(line.split()[0])
        except (subprocess.SubprocessError, OSError):
            pass
    try:
        for entry in json.loads(command('ip', '-j', '-4', 'neighbour', 'show', 'dev', device)):
            add(entry.get('dst', ''))
    except (subprocess.SubprocessError, OSError, ValueError):
        pass
    for address in candidates[:priority_count]:
        if verify(address, config):
            return {'home': True, 'address': address}
    hints = set(candidates)
    candidates = candidates[priority_count:] + [str(ip) for ip in subnet.hosts() if str(ip) not in own | hints]
    # Neighbour hints can fill the subnet after a scan; keep them concurrent too.
    # Finite discovery only: one port, one allowed /24, at most sixteen probes at once.
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        futures = {pool.submit(verify, a, config): a for a in candidates}
        for future in concurrent.futures.as_completed(futures):
            if future.result():
                for pending in futures:
                    pending.cancel()
                return {'home': True, 'address': futures[future]}
    return {'home': True, 'address': ''}


if __name__ == '__main__':
    try:
        config = json.loads(Path(sys.argv[1]).read_text())
        result = discover(config, sys.argv[2] if len(sys.argv) > 2 else '')
    except (OSError, ValueError, KeyError, IndexError, subprocess.SubprocessError):
        result = {'home': False, 'address': '', 'error': 'Phone discovery configuration or network unavailable'}
    print(json.dumps(result))
