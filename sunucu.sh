#!/bin/bash
SERVERNAME="Default"
VGROUP="virt-images-1"  # default volume group name
VGPATH="/dev/$VGROUP"  #volume group path
HNAME=".kartaca.net"

set -e

#  ROOT KONTROLÜ
if [ "$(id -u)" != "0" ];
then
    echo "
        !!!! BETİĞİ ÇALIŞTIRMAK İÇİN ROOT OLMANIZ GEREKİYOR
        "
    exit 0
fi


function HELP(){

    echo "
        -----  KVM SUNUCU ACMA BETİĞİ -----

        -s  >>>  ayarı sunucu adını ayarlamak için kullanılır.

        -b  >>>  ayarı kullanacağımız base image adıdır

        -P  >>>	 ayarı path içindir.
                 default olarak  :  VOLUME GRUOP ADIMIZ default olarak virt-images-1 ise
                 VGPATH = /dev/virt-images-1/
                 VOLUME GROUP ADIMIZ virt-images-1 degil ise
                 -L  ayarı ile VOLUME GROUP adını vermeliyiz.

        -I  >>>  ayarı server ip adresini ayarlamak için kullanılır.
                 BU AYAR GİRİLMİS İSE DİGER BÜTÜN NETWORK AYARLARI GİRİLMEK ZORUNDADIR!!!
                 $0 -s debian -b jessie-base2 -I 1.1.1.1 -n 2.2.2.2 -N 3.3.3.3 -G 4.4.4.4 -B 5.5.5.5 -D 8.8.8.8

        -n  >>>  ayarı server netmask içindir

        -N  >>>  ayarı server network ayarı içindir

        -G  >>>  ayarı gateway içindir

        -B  >>>  ayarı broadcast içindir

        -D  >>>  ayarı dns nameserver içindir

        -L  >>>  ayarı logical volume ismi içindir
                 VOLUME GROUP adı  virt-images-1 dir. Eger VOLUME GROUP adı virt-images-1 den
                 farklı ise  -L parametresi ile VOLUME GROUP adını veriniz.

        -H  >>>  ayarı hostname ayarlamak içindir. default olarak  .kartaca.net
                 örnek kullanım   -H .kartaca.com


                örnek kullanım :

                $0 -s debian -b jessie-base2 -I 1.1.1.1 -n 2.2.2.2 -N 3.3.3.3 -G 4.4.4.4 -B 5.5.5.5 -D 8.8.8.8

"

    exit 1
}

# network ayarı kontrol fonksiyonu
function valid_network()
{
    local  option=$1
    local  result=1

    if [[ $option =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]];
    then
        IFS='.'
        option=($option)
        [[ ${option[0]} -le 255 && ${option[1]} -le 255 \
            && ${option[2]} -le 255 && ${option[3]} -le 255 ]]
        result=$?
    fi
    return $result
}

## ayarların tanımları
while getopts "hs:b:I:n:N:G:B:D:P:L:H:": opt;
do   case $opt in
        h)      HELP
                ;;

        s)      SERVERNAME=$OPTARG
                ;;

        b)      BASENAME=$OPTARG
                ;;

        I)      IPADDRESS=$OPTARG
                ;;

        n)      NETMASK=$OPTARG
                ;;

        N)      NETWORK=$OPTARG
                ;;

        G)      GATEWAY=$OPTARG
                ;;

        B)      BROADCAST=$OPTARG
                ;;

        D)      DNSNAMESERVER=$OPTARG
                ;;

        P)      VGPATH=$OPTARG
                ;;

        L)      VGROUP=$OPTARG
                ;;

        H)      HNAME=$OPTARG
                ;;
       esac
done

## logical volume kontrolü
if  (lvdisplay | grep -o "$VGPATH/$SERVERNAME$" ) ;
then
    echo -e "\n\n !!!   $SERVERNAME İSİMDE BİR LOGICAL VOLUME VAR"
    exit 2
fi

# sunucu adı kontrolü
if (virsh list --all --name | grep -o "$SERVERNAME$");
then
    echo -e "\n\n  !!! $SERVERNAME İSMİNDE BİR SUNUCU VAR !!\n\n"
    exit 3
fi

if [ $SERVERNAME = "Default" ];
then
    echo "\n\n!!!SUNUCU ADINI GİRİNİZ !!!\n\n"
    exit 4
fi

### network ayarlarının kontrol edilmesi
if $(valid_network $IPADDRESS) && $(valid_network $GATEWAY) && $(valid_network $NETWORK) \
   && $(valid_network $NETMASK ) && $(valid_network $DNSNAMESERVER) && $(valid_network $BROADCAST) ;
then
   echo -e "\n\n NETWORK AYARLARI DOĞRU GİRİLDİ \n\n"
else
   echo -e "\n\n!!!NETWORK AYARLARINDA BİR HATA VAR\n\n"
   exit 5
fi
##  geçici logical volume oluşturuluyor
if lvcreate -L 4G -n "$SERVERNAME-temp" "$VGROUP";
then
    echo -e "\n!!!! LOGICAL VOLUME OLUŞTURULDU\n"
else
    echo -e "\n\n!!!! LOGICAL VOLUME OLUŞTURULAMADI\n\n"
    exit 6
fi
#### logical volume oluşruluyor
if lvcreate -L 16G -n "$SERVERNAME" "$VGROUP" ;
then
    echo -e "\n!!!! LOGICAL VOLUME OLUŞTURULDU\n"
else
    echo -e "\n!!!! LOGICAL VOLUME OLUŞTURULAMADI \nOLUŞTURULAN GEÇİCİ LOGICAL VOLUME SİLİNİYOR !!\n"
    # hatalı oluşan logical volume siliniyor.
    lvremove "$VGPATH/$SERVERNAME-temp"
    exit 7
fi

virt-clone --original "$BASENAME" --name "$SERVERNAME" --file "$VGPATH/$SERVERNAME-temp" --mac RANDOM --replace --force

virt-sysprep -d "$SERVERNAME" --hostname "$SERVERNAME" --enable cron-spool,dhcp-client-state,dhcp-server-state,logfiles,mail-spool,net-hwaddr,ssh-hostkeys,udev-persistent-net,utmp

virsh dumpxml "$SERVERNAME" > "$SERVERNAME.xml"
sed -i "s:$SERVERNAME-temp:$SERVERNAME:" "$SERVERNAME.xml"
virsh define "$SERVERNAME.xml"
rm "$SERVERNAME.xml"

virt-resize --expand /dev/sda1 "$VGPATH/$SERVERNAME-temp" "$VGPATH/$SERVERNAME"

lvremove "$VGPATH/$SERVERNAME-temp"

touch hosts interfaces
echo -e "# This file describes the network interfaces available on your system\n# and how to activate them. For more information, see interfaces(5).
source /etc/network/interfaces.d/*\n# The loopback network interface\nauto lo\niface lo inet loopback\n\n#The primary network interfacesallow-hotplug eth0
iface eth0 inet static\n\taddress $IPADDRESS\n\tnetmask $NETMASK\n\tnetwork $NETWORK\n\tbroadcast $BROADCAST\n\tgateway $GATEWAY\n\tdns-nameserver $DNSNAMESERVER" > interfaces

if [ $HNAME != ".kartaca.net" ];
then
    echo -e "127.0.0.1\t$SERVERNAME$HNAME\t$SERVERNAME" > hosts
else
    echo -e "127.0.0.1\t$SERVERNAME.kartaca.net\t$SERVERNAME" > hosts
fi

virt-copy-in -d "$SERVERNAME" hosts /etc
virt-copy-in -d "$SERVERNAME" interfaces /etc/network
rm hosts interfaces

virsh list --all

virsh start "$SERVERNAME"
