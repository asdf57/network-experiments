# Active–Passive VIP Failover Lab (with Linux macvlan + netns)

This repo contains a self-contained Bash script that demonstrates how active–passive failover with a Virtual IP (VIP) works in Linux.

The experiment uses network namespaces and macvlan interfaces to simulate two “nodes” that share a VIP. When one goes down, the VIP fails over to the other.

# Goals of the Experiment
- Learn how a Virtual IP address can move between nodes.
- Observe the failover process and how ARP updates propagate.
- Understand Linux networking behaviors such as:
    - Local delivery (packets to a local IP never leave the host).
    - macvlan quirks (parent interface cannot directly talk to its children).
- Why a proper gateway is required for cross-subnet routing.
- Why the loopback (lo) interface needs to be brought up in new namespaces.

# Execution
## Node running script
```
➔ ./experiment.sh; 
[INFO] Setting up network namespaces...
[INFO] Setting up mcv0 interface in namespace ns0...
[INFO] Setting up mcv1 interface in namespace ns1...
[INFO] Setting up mcv-client interface in default namespace...
[INFO] Bringing up mcv-client and assigning IP...
[INFO] Initial ARP entry for VIP 10.3.2.200: 02:00:00:00:00:10

You should notice that pings are resolving. The MAC should be 02:00:00:00:00:10

[INFO] Performing failover in 10...
[INFO] Performing failover in 9...
[INFO] Performing failover in 8...
[INFO] Performing failover in 7...
[INFO] Performing failover in 6...
[INFO] Performing failover in 5...
[INFO] Performing failover in 4...
[INFO] Performing failover in 3...
[INFO] Performing failover in 2...
[INFO] Performing failover in 1...
[INFO] Bringing down iface mcv0...
[INFO] Failing over VIP to ns1...

Right now, pings should NOT be going through (ARP entry is stale)

[INFO] Sending out gratuitous ARP for new MAC in 10...
[INFO] Sending out gratuitous ARP for new MAC in 9...
[INFO] Sending out gratuitous ARP for new MAC in 8...
[INFO] Sending out gratuitous ARP for new MAC in 7...
[INFO] Sending out gratuitous ARP for new MAC in 6...
[INFO] Sending out gratuitous ARP for new MAC in 5...
[INFO] Sending out gratuitous ARP for new MAC in 4...
[INFO] Sending out gratuitous ARP for new MAC in 3...
[INFO] Sending out gratuitous ARP for new MAC in 2...
[INFO] Sending out gratuitous ARP for new MAC in 1...

You should notice that pings are resolving. The MAC should be 02:00:00:00:00:11

^C[INFO] Cleaning up resources...
```

## External node on same subnet
- Before failover, we can see that the MAC corresponding to the VIP belongs to mcv0:
```
[admin@MikroTik] > /ip arp print where address=10.3.2.200
Flags: D - DYNAMIC; C - COMPLETE
Columns: ADDRESS, MAC-ADDRESS, INTERFACE
#    ADDRESS     MAC-ADDRESS        INTERFACE
0 DC 10.3.2.200  02:00:00:00:00:10  bridge   
```

- After failover, we find that the MAC for the VIP now corresponds to mcv1:
```
[admin@MikroTik] > /ip arp print where address=10.3.2.200
Flags: D - DYNAMIC; C - COMPLETE
Columns: ADDRESS, MAC-ADDRESS, INTERFACE
#    ADDRESS     MAC-ADDRESS        INTERFACE
0 DC 10.3.2.200  02:00:00:00:00:11  bridge   
```

- Pings during the failover:
```
root@archiso ~ # ping 10.3.2.200
PING 10.3.2.200 (10.3.2.200) 56(84) bytes of data.
64 bytes from 10.3.2.200: icmp_seq=1 ttl=64 time=0.163 ms
64 bytes from 10.3.2.200: icmp_seq=2 ttl=64 time=0.177 ms
64 bytes from 10.3.2.200: icmp_seq=3 ttl=64 time=0.209 ms
64 bytes from 10.3.2.200: icmp_seq=4 ttl=64 time=0.174 ms
64 bytes from 10.3.2.200: icmp_seq=5 ttl=64 time=0.145 ms
64 bytes from 10.3.2.200: icmp_seq=6 ttl=64 time=0.182 ms
64 bytes from 10.3.2.200: icmp_seq=7 ttl=64 time=0.145 ms
64 bytes from 10.3.2.200: icmp_seq=8 ttl=64 time=0.186 ms
64 bytes from 10.3.2.200: icmp_seq=9 ttl=64 time=0.176 ms
64 bytes from 10.3.2.200: icmp_seq=10 ttl=64 time=0.169 ms

# This gap represents the failover (but before the gratuitous ARP was sent)

64 bytes from 10.3.2.200: icmp_seq=21 ttl=64 time=0.288 ms
64 bytes from 10.3.2.200: icmp_seq=22 ttl=64 time=0.142 ms
64 bytes from 10.3.2.200: icmp_seq=23 ttl=64 time=0.146 ms
64 bytes from 10.3.2.200: icmp_seq=24 ttl=64 time=0.141 ms
^C
--- 10.3.2.200 ping statistics ---
24 packets transmitted, 14 received, 41.6667% packet loss, time 23591ms
rtt min/avg/max/mdev = 0.141/0.174/0.288/0.037 ms
```