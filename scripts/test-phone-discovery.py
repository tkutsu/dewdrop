#!/usr/bin/env python3
"""Check discovery bounds, saved-network gating and proof validation without LAN traffic."""
import hashlib
import importlib.util
import io
import ipaddress
import json
import threading
import time
from pathlib import Path
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('discovery',Path(__file__).with_name('phone-discover.py'))
discovery=importlib.util.module_from_spec(spec);spec.loader.exec_module(discovery)
CONFIG=dict(port=8080,secret='a'*64,pairId='b'*32,address='192.168.1.99',hostname='',homeNetworks=[dict(uuid='saved-home',cidr='192.168.1.0/24',ssid='Home')])


class DiscoveryTests(unittest.TestCase):
    def test_other_saved_network_never_probes(self):
        with patch.object(discovery,'command',return_value='different:802-11-wireless:wlan0'),patch.object(discovery,'verify') as probe:
            self.assertEqual(discovery.discover(CONFIG),dict(home=False,address=''))
            probe.assert_not_called()

    def test_ip_change_is_found_within_allowed_subnet(self):
        candidates=[]
        def probe(address, config):
            candidates.append(address)
            return address=='192.168.1.121'
        network=('wlan0',ipaddress.ip_network('192.168.1.0/24'),{'192.168.1.105'})
        with patch.object(discovery,'home_network',return_value=network),patch.object(discovery,'command',return_value='[]'),patch.object(discovery,'verify',side_effect=probe):
            result=discovery.discover(CONFIG,'203.0.113.7')
        self.assertEqual(result['address'],'192.168.1.121')
        self.assertTrue(all(ipaddress.ip_address(a) in network[1] for a in candidates))
        self.assertNotIn('192.168.1.105',candidates)
        self.assertEqual(candidates[0],'192.168.1.99')

    def test_stale_neighbour_table_does_not_serialize_subnet_scan(self):
        network=('wlan0',ipaddress.ip_network('192.168.1.0/26'),{'192.168.1.2'})
        neighbours=json.dumps([dict(dst=str(ip)) for ip in network[1].hosts()])
        lock=threading.Lock()
        active=peak=0
        def probe(address, config):
            nonlocal active,peak
            with lock:
                active+=1
                peak=max(peak,active)
            time.sleep(.01)
            with lock: active-=1
            return False
        cfg=dict(CONFIG,address='192.168.1.3')
        with patch.object(discovery,'home_network',return_value=network),patch.object(discovery,'command',return_value=neighbours),patch.object(discovery,'verify',side_effect=probe):
            self.assertEqual(discovery.discover(cfg),dict(home=True,address=''))
        self.assertGreater(peak,1,'Neighbour hints must use the bounded concurrent scan')
        self.assertLessEqual(peak,16)

    def test_challenge_contains_no_secret_and_rejects_wrong_peer(self):
        class Opener:
            correct=True
            def open(self, request, timeout):
                body=json.loads(request.data)
                self_outer.assertEqual(set(body),{'op','nonce'})
                self_outer.assertNotIn(CONFIG['secret'],request.data.decode())
                nonce=body['nonce'];proof=hashlib.sha256((CONFIG['secret']+':'+nonce).encode()).hexdigest()
                return io.BytesIO(json.dumps(dict(v=1,pairId=CONFIG['pairId'],nonce=nonce,proof=proof if self.correct else 'wrong')).encode())
        self_outer=self;opener=Opener()
        with patch.object(discovery.urllib.request,'build_opener',return_value=opener):
            self.assertTrue(discovery.verify('192.168.1.121',CONFIG))
            opener.correct=False
            self.assertFalse(discovery.verify('192.168.1.121',CONFIG))

    def test_large_or_public_subnet_is_rejected(self):
        for cidr in ('192.168.0.0/16','8.8.8.0/24'):
            cfg=dict(CONFIG,homeNetworks=[dict(uuid='saved-home',cidr=cidr)])
            with patch.object(discovery,'command',return_value='saved-home:802-11-wireless:wlan0'):
                with self.assertRaises(ValueError): discovery.home_network(cfg)


if __name__=='__main__': unittest.main()
