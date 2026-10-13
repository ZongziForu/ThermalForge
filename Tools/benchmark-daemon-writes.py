#!/usr/bin/env python3
"""Short local latency check. GUI must be stopped and daemon have no existing hold.
Temporarily runs fans at their hardware minimum; always returns to Apple auto.
No thermal workload or calibration is launched.
"""
import argparse
import json
import socket
import struct
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', required=True)
args = parser.parse_args()
if subprocess.run(['pgrep', '-x', 'ThermalForgeApp'], stdout=subprocess.DEVNULL).returncode == 0:
    raise SystemExit('Stop the GUI before running this short latency check.')

def request(verb, **fields):
    body = json.dumps(dict(v=1, verb=verb, oneshot=False, **fields)).encode()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(15)
        connection.connect('/var/run/thermalforge.sock')
        connection.sendall(struct.pack('>I', len(body)) + body)
        def receive(count):
            data = b''
            while len(data) < count:
                part = connection.recv(count-len(data))
                if not part:
                    raise RuntimeError('Unexpected daemon EOF')
                data += part
            return data
        count = struct.unpack('>I', receive(4))[0]
        if count > 65536:
            raise RuntimeError('Unexpected response length')
        response = json.loads(receive(count))
    if not response.get('ok'):
        raise RuntimeError(str(response))
    return response

if request('state')['state']['owner'] != 'none':
    raise SystemExit('Existing fan hold detected; refusing to overwrite it.')
version = request('version')['version']
status = json.loads(subprocess.check_output(['/usr/local/bin/thermalforge', 'status']))
fans = status['fans']
if not fans:
    raise SystemExit('No fans detected.')
rpm = max(fan['min_rpm'] for fan in fans)
if rpm <= 0 or rpm > min(fan['max_rpm'] for fan in fans):
    raise SystemExit('Unusable fan limits.')
results = []
try:
    for index in range(4):
        start = time.perf_counter()
        response = request('set', rpm=rpm)
        results.append(dict(command=index+1, seconds=time.perf_counter()-start,
                            applied_rpm=response.get('appliedRPM')))
        time.sleep(0.6)  # Keep comfortably below the daemon's write rate limit.
finally:
    request('auto')
    if request('state')['state']['owner'] != 'none':
        raise RuntimeError('Auto reset was not confirmed.')
report = dict(version=version, rpm=rpm, results=results, restored_auto=True)
with open(args.output, 'w') as output:
    json.dump(report, output, indent=2)
print(json.dumps(report, indent=2))
