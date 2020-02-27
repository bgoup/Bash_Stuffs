#!/bin/bash

echo "Setup Start"
echo "Begining apt setup..."
# apt sources setup
read -re -p "Replace sources.list with custom one?
$(uname -a)
y/n [n]: " USER_INPUT
case $USER_INPUT in
	y|Y)
		if  grep 'Debian GNU/Linux 8' /etc/apt/sources.list
		then
			echo "Detected Debian 8 Jessie."
			read -re -p "Press enter to continue."
			rm /etc/apt/sources.list
			wget "http://web2.goup.io/resources/sources.list.deb8" -O /etc/apt/sources.list
		elif grep 'Debian GNU/Linux 9' /etc/apt/sources.list
		then
			echo "Detected Debian 9 Stretch."
			read -re -p "Press enter to continue."
			rm /etc/apt/sources.list
			wget "http://web2.goup.io/resources/sources.list.deb9" -O /etc/apt/sources.list
		else
			echo "ERROR! Can't detect OS version!"
			exit 1
		fi
		echo "New sources.list:"
		cat /etc/apt/sources.list
		read -re -p "Press enter to continue."
		;;
	*)
		echo "Skipping sources.list changes."
	;;
esac
echo "Running apt-get update..."
apt-get update
echo "Apt setup complete."
# software install
	# basics
echo "Installing basics utilities..."
apt-get purge iptables -y
apt-get install openssh-server rsync net-tools smbclient unattended-upgrades ntp ntpdate -y
#sed -i -e 'r|//Unattended-Upgrade::Automatic-Reboot-Time "02:00"|Unattended-Upgrade::Automatic-Reboot-Time "02:00"|g' /etc/apt/apt.conf.d
echo "Finished installing basics."
	# zabbix agent
read -re -p "Install the zabbix agent?
y/[n]: " USER_INPUT
case $USER_INPUT in
	y|Y)
		if  grep 'Debian GNU/Linux 8' /etc/apt/sources.list
		then
			echo "Detected Debian 8 Jessie."
			read -re -p "Press enter to continue."
			echo "Begining zabbix agent install..."
			wget "http://web2.goup.io/resources/zabbix-agent-deb8.deb"
			dpkg -i "zabbix-agent-deb8.deb"
			rm "zabbix-agent-deb8.deb"
		elif grep 'Debian GNU/Linux 9' /etc/apt/sources.list
		then
			echo "Detected Debian 9 Stretch."
			read -re -p "Press enter to continue."
			echo "Begining zabbix agent install..."
			wget "http://web2.goup.io/resources/zabbix-agent-deb9.deb"
			dpkg -i "zabbix-agent-deb9.deb"
			rm "zabbix-agent-deb9.deb"
		else
			echo "ERROR! Can't detect OS version!"
			exit 1
		fi
		
		apt-get update
		apt-get install zabbix-agent -y
		sed 'r/^Server=/Server=25.0.0.31/' /etc/zabbix/zabbix_agentd.conf
		sed 'r/^Hostname=/Hostname=$HOSTNAME/' /etc/zabbix/zabbix_agentd.conf
		service zabbix-agent start
		echo "Finished zabbix agent install."
	;;
		
	*)
		echo "Skipping zabbix agent install."
	;;
esac
	# webmin install
read -re -p "Install webmin?
y/[n]: " USER_INPUT
case $USER_INPUT in
	y|Y)
		wget "http://web2.goup.io/resources/webmin.deb"
		apt-get install wget curl perl -y
		dpkg -i webmin.deb
		apt-get install -f -y
		rm webmin.deb
		echo "Finished webmin install."
	;;
	*)
		echo "Skipping webmin install."
	;;
esac
echo "Finished installing software."
# network setup
	# IP
echo "Start Network setup..."
read -re -p "IP address config:
$(ip addr)
Format:
	address [ipaddr/subnet] ex: 25.0.0.50/24
	gateway [ipaddr] ex: 25.0.0.1
edit the IP address settings? y/[n]" USER_INPUT
case $USER_INPUT in
	y|Y)
		nano /etc/network/interfaces
	;;
	*)
		echo "Skipping IP address config:"
	;;
esac
	# DNS
read -re -p "DNS server config:
$(cat /etc/resolv.conf)
edit the DNS server settings? y/[n]" USER_INPUT
case $USER_INPUT in
	y|Y)
		nano /etc/resolv.conf
	;;
	*)
		echo "Skipping DNS server config:"
	;;
esac
echo "Finished network setup."

echo "END script"
exit 0
