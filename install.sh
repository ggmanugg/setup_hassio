#!/bin/bash

#######################################################################
#Setup Home Assistant on an Ubuntu Server 18.04 LTS                   #
#This script just include the basic installation                      #
#This script is written by ggmanugg                                   #
#[C] 2018 Manuel Berger                                               #
#######################################################################

#Check root
if [[ $EUID -ne 0 ]]; then
   echo This script must be run as root
   exit 1
fi

#User name
echo Enter your current username:
read usern

#Domain name
echo Enter your duckdns domain name e.g. test.duckdns.org:
read domain

#Duckdns token
echo Enter your duckdns token:
read token

#Letsencrypt challenge 
echo Which challenge should be used? Currently http-01 and dns-01 are supported
oldIFS=$IFS
IFS=$'\n'
choices=( http-01 dns-01 )
IFS=$oldIFS
PS3="Please enter your choice: "
select answer in "${choices[@]}"; do
  for item in "${choices[@]}"; do
    if [[ $item == $answer ]]; then
      break 2
    fi
  done
done

#Up-to-date
sudo apt-get update
sudo apt-get upgrade -y

#Install prerequisites
sudo apt-get install python3-pip python3-venv -y

#Setup virtual environment
cd ..
sudo python3 -m venv homeassistant

source /home/"$usern"/homeassistant/bin/activate && python3 -m pip install wheel

#Install Home Assistant
source /home/"$usern"/homeassistant/bin/activate && python3 -m pip install homeassistant

#Setup hass service
source /home/"$usern"/homeassistant/bin/activate && hasslocation=$(echo $(whereis hass)|awk '{print $2}')
sudo rm /etc/systemd/system/homeassistant@$usern.service
sudo touch /etc/systemd/system/homeassistant@$usern.service
sudo cat >> /etc/systemd/system/homeassistant@$usern.service <<EOF
[Unit]
Description=Home Assistant
After=network-online.target

[Service]
Type=simple
User=%i
ExecStart=$hasslocation -c '/home/$usern/.homeassistant'

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable homeassistant@$usern.service
sudo systemctl start homeassistant@$usern.service

#Begin duckdns letsencrypt

#Prerequisites
sudo rm -r ~/dehydrated

#Download prerequisites
git clone https://github.com/lukas2511/dehydrated.git ~/dehydrated

#Setup dehydrated
touch ~/dehydrated/domains.txt
cat >> ~/dehydrated/domains.txt << EOF
$domain
EOF
sudo cp ~/build_hassio/config ~/dehydrated/
sudo sed -i -e "s/answer/$answer/g" ~/dehydrated/config

#Setup hook.sh
sudo cp ~/build_hassio/hook.sh ~/dehydrated/
sudo sed -i -e "s/ind/$domain/g" ~/dehydrated/hook.sh
sudo sed -i -e "s/int/$token/g" ~/dehydrated/hook.sh
sudo sed -i -e "s/usern/$usern/g" ~/dehydrated/hook.sh
sudo chmod 755 ~/dehydrated/hook.sh

#Generate certificate
cd ~/dehydrated
sudo ./dehydrated --register  --accept-terms
sudo ./dehydrated -c

#Add certificate to home assistant
cert=$(echo $(sudo find /home/admin/dehydrated/certs/ -name "fullchain.pem"))
key=$(echo $(sudo find /home/admin/dehydrated/certs/ -name "privkey.pem*"))

sed -i '/^http\:/a \ \ base_url\: '"$domain"':8123' ~/.homeassistant/configuration.yaml
sed -i '/^http\:/a \ \ ssl_certificate\: '"$cert"'' ~/.homeassistant/configuration.yaml
sed -i '/^http\:/a \ \ ssl_key\: '"$key"'' ~/.homeassistant/configuration.yaml

#Restart home assistant
sudo systemctl restart homeassistant@$usern.service

#Clean up
clear
cat << "EOF"
  _____ ___ _   _ ___ ____  _   _ 
 |  ___|_ _| \ | |_ _/ ___|| | | |
 | |_   | ||  \| || |\___ \| |_| |
 |  _|  | || |\  || | ___) |  _  |
 |_|   |___|_| \_|___|____/|_| |_|    
EOF
echo \n
echo Go to https://ipaddress:8123 and enjoy your Home Assistant
