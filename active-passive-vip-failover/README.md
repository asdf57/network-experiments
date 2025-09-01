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
