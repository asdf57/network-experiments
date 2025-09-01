#!/usr/bin/env bash

# The goal of this script is to teach me about active-passive
# failover with a VIP. From this experiment, I expect to observe
# how we assign a VIP and how the failover process works. This
# includes seeing the traffic automatically routing from dummy0
# to dummy1.

# My network topology is as follows:
# [node] <-> [192.168.1.0/24 Network] <-> [10.0.0.0/8 Network] <-> [this node w/ macvlan ifaces]

### MACVLAN configuration ###
MACVLAN_NETWORK="10.3.2"
MACVLAN_PREFIX="8"
NS0_IFACE_CIDR="${MACVLAN_NETWORK}.210/${MACVLAN_PREFIX}"
NS1_IFACE_CIDR="${MACVLAN_NETWORK}.211/${MACVLAN_PREFIX}"
DEFAULT_NS_IFACE_CIDR="${MACVLAN_NETWORK}.212/${MACVLAN_PREFIX}"

GATEWAY="10.1.1.1"                  # Change this to your actual gateway
VIP="${MACVLAN_NETWORK}.200"     # Change this to your desired VIP
VIP_CIDR="${VIP}/8"              # Change this if you want a different VIP CIDR
PARENT="enp7s0"                     # Change this to your actual iface
MAC1="02:00:00:00:00:10"            # Change this to your desired MAC for iface1
MAC2="02:00:00:00:00:11"            # Change this to your desired MAC for iface2

log_info()    { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_warn()    { echo -e "\033[1;33m[WARN]\033[0m $*"; }
log_error()   { echo -e "\033[1;31m[ERROR]\033[0m $*"; }
log_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $*"; }

# Cleanup resources after use
function cleanup() {
    log_info "Cleaning up resources..."
    sudo ip netns del ns0 2>/dev/null || true
    sudo ip netns del ns1 2>/dev/null || true
    sudo ip link del mcv-client 2>/dev/null || true
}

trap cleanup EXIT

# When you send traffic to an IP that belongs
# to a local interface, Linux treats it as loopback
# traffic. Hence, this test will NOT work as is.
# This is called LOCAL DELIVERY in the Linux IP stack!
# Solution is either two separate hosts OR two network
# namespaces. I'm using the latter in this example.

# A network NS is a logical network representation in Linux.
# Each has its own ifaces, routing table, ARP cache, firewall
# rules, etc. Namespaces CANNOT see each other's ifaces
# or IPs directly unless connected via virtual link. We take
# advantage of this property in the lab (see below)
log_info "Setting up network namespaces..."
sudo ip netns add ns0
sudo ip netns add ns1

log_info "Setting up mcv0 interface in namespace ns0..."
sudo ip link add mcv0 link $PARENT address $MAC1 type macvlan mode bridge
sudo ip link set mcv0 netns ns0

log_info "Setting up mcv1 interface in namespace ns1..."
sudo ip link add mcv1 link $PARENT address $MAC2 type macvlan mode bridge
sudo ip link set mcv1 netns ns1

# NOTE: macvlan has a quirk where the parent iface CANNOT communicate
# with the macvlan ifaces under it. To get around this, we create another
# macvlan iface in the default namespace that's in the SAME subnet as the
# other macvlan ifaces. This allows the host computer to communicate with
# those ifaces.
log_info "Setting up mcv-client interface in default namespace..."
sudo ip link add mcv-client link $PARENT type macvlan mode bridge

log_info "Bringing up mcv-client and assigning IP..."
sudo ip link set mcv-client up
sudo ip addr add "${DEFAULT_NS_IFACE_CIDR}" dev mcv-client

# NOTE: Upping lo is just a best practice (starts out as down in a new NS)
sudo ip netns exec ns0 ip link set lo up
sudo ip netns exec ns0 ip link set mcv0 up
sudo ip netns exec ns0 ip addr add "${NS0_IFACE_CIDR}" dev mcv0
# NOTE: Using "sudo ip netns exec ns0 ip route add default dev mcv0" does not work.
# This command creates a link-scope default route (shove packets out mcv0 if no matches)
# It works only for directly connected destinations on the same subnet, which is not the
# case if traversing between different subnets. We need a proper gateway for routing.
sudo ip netns exec ns0 ip route add default via $GATEWAY

sudo ip netns exec ns1 ip link set lo up
sudo ip netns exec ns1 ip link set mcv1 up
sudo ip netns exec ns1 ip addr add "${NS1_IFACE_CIDR}" dev mcv1
sudo ip netns exec ns1 ip route add default via $GATEWAY

# Assign the VIP to mcv0 in ns0 to start
sudo ip netns exec ns0 ip addr add $VIP_CIDR dev mcv0

# Send out a gratuitous ARP for the VIP from mcv0 in ns0.
# Updates any stale ARP caches on network devices.
sudo ip netns exec ns0 arping -A -c 2 -I mcv0 $VIP >/dev/null 2>&1

log_info "Initial ARP entry for VIP $VIP: $MAC1"

echo
echo "You should notice that pings are resolving. The MAC should be $MAC1"
echo

for i in {10..1..-1}; do
    log_info "Performing failover in $i..."
    sleep 1
done

log_info "Bringing down iface mcv0..."
sudo ip netns exec ns0 ip link set mcv0 down

log_info "Failing over VIP to ns1..."
sudo ip netns exec ns0 ip addr del $VIP_CIDR dev mcv0
sudo ip netns exec ns1 ip addr add $VIP_CIDR dev mcv1

echo
echo "Right now, pings should NOT be going through (ARP entry is stale)"
echo

for i in {10..1..-1}; do
    log_info "Sending out gratuitous ARP for new MAC in $i..."
    sleep 1
done

sudo ip netns exec ns1 arping -A -c 2 -I mcv1 $VIP >/dev/null 2>&1

echo
echo "You should notice that pings are resolving. The MAC should be $MAC2"
echo

while true; do
    sleep 1
done
