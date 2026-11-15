#!/usr/bin/env python3
"""Use current ALB private node IPs for the manual's SG-to-SG test route."""
import subprocess
from pathlib import Path
from common import CONFIG, SESSION

lb = SESSION.client('elbv2').describe_load_balancers(Names=[CONFIG['alb_name']])['LoadBalancers'][0]
suffix = lb['LoadBalancerArn'].split('loadbalancer/')[1]
interfaces = SESSION.client('ec2').describe_network_interfaces(Filters=[
    {'Name':'vpc-id', 'Values':[CONFIG['vpc_id']]},
    {'Name':'description', 'Values':['ELB ' + suffix]},
])['NetworkInterfaces']
ips = sorted({i['PrivateIpAddress'] for i in interfaces})
if not ips or not all(ip.startswith('10.105.') for ip in ips):
    raise RuntimeError('No current lab ALB private ENIs found. Do not open public ingress.')
# Use one current node consistently for both tests. Refresh immediately before each run.
text = '\n'.join(line for line in Path('/etc/hosts').read_text().splitlines()
                 if not line.endswith('# credify-5-lab-alb'))
text += f"\n{ips[0]} {CONFIG['alb_dns']} # credify-5-lab-alb\n"
subprocess.run(['sudo','tee','/etc/hosts'], input=text, text=True, stdout=subprocess.DEVNULL, check=True)
print(f"Student 5: {CONFIG['alb_dns']} resolves locally to {ips[0]}; other current nodes: {ips[1:]}")
subprocess.run(['getent','ahostsv4',CONFIG['alb_dns']],check=True)
