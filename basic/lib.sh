#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   lib.sh of /CoreOS/initscripts/Library/basic
#   Description: it contains nm handling and similation tools
#   Author: Petr Sklenar <psklenar@redhat.com>
#   Author: Jan Scotka <jscotka@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2016 Red Hat, Inc.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   library-prefix = init
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 NAME

initscripts/basic - it contains nm handling and simulation tools

=head1 DESCRIPTION

This is library what contains basic function for easier testing of initscripts. Therer are two basic parts: disabling Network Manager
and various simulation libraries for network devices (dummy, tap, veth).

=cut

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Variables
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 VARIABLES

Below is the list of global variables. When writing a new library

=over

=item initPREFIX

default prefix for various names

=item initDEFBRIDGE

default bridge name in case not defined 

=item initBASE_PREFIX

default network ip prefix for /24

=item initSIMULATION

default simulation mode used for complex network scenario

=back

=cut

initPREFIX="i"
initDEFBRIDGE="${initPREFIX}bridge"
initBASE_PREFIX=192.168.98
initDHCPSERVERLOG="/var/tmp/$initPREFIX-server.log"
initSIMULATION=init-sim-tap
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Functions
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 FUNCTIONS

=head2 init-NM

It disable network manager somehow, important to enable befor other testing, to avoid collisions with NM

=cut

init-NM() {
    if rlIsRHEL "<=7"; then
        S=NetworkManager
        if rpm -q $S; then
            rlLog "`service $S status`"
            rlServiceStop $S
            sleep 5
        fi
        S=network
        rlLog "`service $S status`"
        rlServiceStart $S
    else
        rlLog "This does nothing for higher RHEL"
    fi
}
true <<'=cut'
=pod

=head2 init-NM-cleanup

It restore NM back to original state and tries to restore network

=cut

init-NM-cleanup() {
    if rlIsRHEL "<=7"; then
        S=network
        rlServiceRestore $S
        sleep 2
        rlLog "`service $S status`"

        S=NetworkManager
        if rpm -q $S; then
            sleep 5
            rlServiceRestore $S
            sleep 2
            rlLog "`service $S status`"
        fi
    else
        rlLog "This does nothing for higher RHEL"
    fi

}
true <<'=cut'
=pod

=head2 init-DefaultEth

Returns default route interface

=cut

init-DefaultEth(){
    ip route show |grep default |awk '{print $5}'
}
true <<'=cut'
=pod

=head2 init-bridge-add

add interface to Bridge (and create bridge in case not initialized)
     init-bridge-add IFACE [BRIDGE]

=over

=item IFACE

Name of interface

=item BRIDGE

Add interface to bridge BRIDGE, in case not given, put into default bidge. In case you want to not attach to bridge, type "NO" as param

=back

=cut

init-check-ip-bridge-support(){
    if rlIsRHEL "<=7"; then
        return 1
    else
        return 0
    fi
    TEST_BRIDGE=rnd_jhshdaos
    if ip link add name $TEST_BRIDGE type bridge 2>/dev/null; then
         ip link delete $TEST_BRIDGE type bridge
        return 0
    else
        brctl show || yum -y install bridge-utils
        return 1
    fi
}

init-bridge-add(){
    local INTERNALNAME=$1
    local BRIDGE=$2
    if [ "$BRIDGE" = "NO" ]; then
        rlLog "SKIP: attach to bridge"
        return 0
    elif [ -z "$BRIDGE" ]; then
        BRIDGE=$initDEFBRIDGE
    fi
    if init-check-ip-bridge-support; then
        if ! ip a s dev $BRIDGE > /dev/null 2>&1; then
            rlRun "ip link add name $BRIDGE type bridge"
            # disable STP somehow
            rlRun "ip link set dev $BRIDGE type bridge stp_state 0"
            rlRun "ip link set dev $BRIDGE up"
        fi
        rlRun "ip link set $INTERNALNAME master $BRIDGE"
    else
        if ! ip a s dev $BRIDGE > /dev/null 2>&1; then
            rlRun "brctl addbr $BRIDGE"
            rlRun "brctl stp $BRIDGE off"
            rlRun "ip link set dev $BRIDGE up"
        fi
        rlRun "brctl addif $BRIDGE $INTERNALNAME"
    fi
}

true <<'=cut'
=pod

=head2 init-bridge-del

delete interface from Bridge (and delete bridge in case last iface)
     init-bridge-del IFACE

=over

=item IFACE

Name of interface

=back

=cut

init-bridge-del(){
    local INTERNALNAME=$1
    if init-check-ip-bridge-support; then
        local BRIDGE=`ip a s dev $INTERNALNAME | egrep -o  'mtu.*master [^ ]+' |grep -oE '[^ ]+$'`
    else
        local BRIDGE=`brctl show |egrep "no\s+$INTERNALNAME" |cut  -f 1`
    fi
    if [ -z "$BRIDGE" ]; then
        rlLog "SKIP: interface not bridged"
        return 0
    fi
    rlLog "Bridged to: $BRIDGE"
    if init-check-ip-bridge-support; then
        rlRun "ip link set $INTERNALNAME nomaster"
        rlRun "ip link set $INTERNALNAME down"
        if ! bridge link | egrep $BRIDGE; then
            rlRun "ip link set dev $BRIDGE down"
            rlRun "ip link delete  $BRIDGE type bridge"
        fi
    else
        rlRun "brctl delif $BRIDGE $INTERNALNAME"
        if brctl show $BRIDGE | egrep "$BRIDGE\s+\S+\s+\S+\s*$"; then
            rlRun "ip link set dev $BRIDGE down"
            rlRun "brctl delbr $BRIDGE"
        fi
    fi
}
true <<'=cut'
=pod

=head2 init-sim-dummy

add interface type: dummy (and add to bridge default/BRIDGE/NO , NO means no bridging)
     init-sim-dummy IFACE [BRIDGE]

=over

=item IFACE

Name of interface

=item BRIDGE

Add interface to bridge BRIDGE, in case not given, put into default bidge. In case you want to not attach to bridge, type "NO" as param

=back

=cut

init-sim-dummy(){
    local NAME=$1
    rlRun "modprobe dummy"
    rlRun "ip link add $NAME type dummy"
    init-bridge-add $NAME $2
    rlRun "ip link set dev $NAME up"
}

true <<'=cut'
=pod

=head2 init-sim-dummy-cleanup

remove interface type: dummy (and remove from bridge if bridged)
     init-sim-dummy-cleanup IFACE 

=over

=item IFACE

Name of interface

=back

=cut

init-sim-dummy-cleanup(){
    local NAME=$1
    init-bridge-del $NAME
    rlRun "ip link del $NAME type dummy"
    if ip a s dev dummy0; then
        rlRun "ip link del dummy0 type dummy"
    fi
}
true <<'=cut'
=pod

=head2 init-sim-tap

add interface type: tap (and add to bridge default/BRIDGE/NO , NO means no bridging)
     init-sim-tap IFACE [BRIDGE]

=over

=item IFACE

Name of interface

=item BRIDGE

Add interface to bridge BRIDGE, in case not given, put into default bidge. In case you want to not attach to bridge, type "NO" as param

=back

=cut

init-sim-tap(){
    local NAME=$1
    if ip tuntap s; then
        rlRun "ip tuntap add dev $NAME mode tap"
    else
        rpm -q tunctl || yum install -y tunctl
        rlRun "tunctl -t $NAME"
    fi
    init-bridge-add $NAME $2
    rlRun "ip link set dev $NAME up"
}

true <<'=cut'
=pod

=head2 init-sim-tap-cleanup

remove interface type: tap (and remove from bridge if bridged)
     init-sim-tap-cleanup IFACE 

=over

=item IFACE

Name of interface

=back

=cut

init-sim-tap-cleanup(){
    local NAME=$1
    init-bridge-del $NAME
    if ip tuntap s; then
        rlRun "ip tuntap del dev $NAME mode tap"
    else
        rlRun "tunctl -d $NAME"
    fi
}

true <<'=cut'
=pod

=head2 init-sim-veth

add interface type: veth (and add to bridge default/BRIDGE/NO , NO means no bridging)
     init-sim-veth IFACE [BRIDGE]

=over 

=item IFACE

Name of interface

=item BRIDGE

Add interface to bridge BRIDGE, in case not given, put into default bidge. In case you want to not attach to bridge, type "NO" as param

=back

=cut

init-sim-veth(){
    local NAME=$1
    rlRun "ip link add name $NAME-br type veth peer name $NAME"
    rlRun "ip link set dev $NAME-br up"
    rlRun "ip link set dev $NAME up"
    init-bridge-add $NAME-br $2
}

true <<'=cut'
=pod

=head2 init-sim-veth-cleanup

remove interface type: veth (and remove from bridge if bridged)
     init-sim-veth-cleanup IFACE 

=over 

=item IFACE

Name of interface

=back

=cut

init-sim-veth-cleanup(){
    local NAME=$1
    rlRun "ip link set dev $NAME down"
    rlRun "ip link set dev $NAME-br down"
    init-bridge-del $NAME-br
    rlRun "ip link del $NAME"
}

init-netns-addif(){
    local NAMESPACE=$1
    shift
    ip netns show | egrep -s "^${NAMESPACE}\$" || rlRun "ip netns add ${NAMESPACE}"
    for NIF in "$@"; do
        rlRun "ip link set ${NIF} netns ${NAMESPACE}"
        rlRun "init-netns-execute ${NAMESPACE} ip link set dev ${NIF} up"
    done
}

init-netns-execute(){
    local NAMESPACE=$1
    shift
    ip netns exec ${NAMESPACE} "$@"
}

init-netns-cleanup(){
    local NAMESPACE=$1
    shift
    for NIF in "$@"; do
        rlRun "init-netns-execute ${NAMESPACE} ip link del ${NIF}"
    done
    rlRun "ip netns del ${NAMESPACE}"
}



true <<'=cut'
=pod

=head2 init-dhcp

run dnsmasq on interface with default network prefix (100-199 as extension)
     init-dhcp IFACE 

=over

=item IFACE

Name of interface

=back

=cut

init-dhcp(){
    local IFACE=$1
    local LLL=17
    local ADR_DHCP=$initBASE_PREFIX.$LLL
    rlRun "ip a a $ADR_DHCP/24 dev $IFACE"
    local RANGE=$initBASE_PREFIX.100,$initBASE_PREFIX.199
    /usr/sbin/dnsmasq -d --log-dhcp --bind-interfaces --listen-address=$ADR_DHCP --dhcp-range=$RANGE --leasefile-ro -p 0 > $initDHCPSERVERLOG 2>&1 &
    export __DHCP_PID=$!
    rlRun "sleep 3"
    rlRun "cat /proc/$__DHCP_PID/cmdline | grep '/usr/sbin/dnsmasq'"
}

true <<'=cut'
=pod

=head2 init-dhcp-log

Print dhcpmasq server log

=cut

init-dhcp-log(){
    cat $initDHCPSERVERLOG
}

true <<'=cut'
=pod

=head2 init-dhcp-cleanup

Kill internal dhcp server and send dhcp log to beaker

=cut

init-dhcp-cleanup(){
    rlRun "kill $__DHCP_PID"
    rlSubmitFile $initDHCPSERVERLOG
    rlRun "rm -vf $initDHCPSERVERLOG"
}

true <<'=cut'
=pod

=head2 init-ifcfg-simple

Generate simple ifcfg file.
It returns name of generated file as last line of output
    init-ifcfg-simple {IFACE} [none|dhcp|static] [IPADDR[/PREFIX]]

=over

=item IFACE

Name of interface to generate ifcfg file

=item [none|dhcp|static]

Various methods as BOOTPROTO (none= no IP addr, just file, dhcp= use dhcp server, static= add ip addr, if not given use default one)

=item [IPADDR[/PREFIX]]

when used static as BOOTPROTO, use given IP, default prefix is /24 if not given

=back

=cut

init-ifcfg-simple(){
    local NAME=$1
    local PROTO=$2
    local ADR=$3    
    test -z "$PROTO" && PROTO="none"
    test -z "$ADR" && ADR=$initBASE_PREFIX.1
    echo "$ADR" | grep -sq "/" || ADR=$ADR/24
    echo "DEVICE=\"$NAME\"
BOOTPROTO=\"$PROTO\"
NM_CONTROLLED=\"yes\"
ONBOOT=\"no\"" > /etc/sysconfig/network-scripts/ifcfg-$NAME
    if [ "$PROTO" = "none" ]; then
        rlLog "PROTO set to none, just created template"
    elif [ "$PROTO" = "dhcp" ]; then
        rlLog "PROTO set to dhcp, you have to set dhcp server"
    elif [ "$PROTO" = "static" ]; then
        echo "`ipcalc -m $ADR`
`ipcalc -n $ADR`
`ipcalc -b $ADR`
IPADDR=`echo $ADR |cut -d / -f 1`" >> /etc/sysconfig/network-scripts/ifcfg-$NAME
        rlLog "PROTO set to static IP adress $ADR"
    fi
    echo /etc/sysconfig/network-scripts/ifcfg-$NAME
}

true <<'=cut'
=pod

=head2 init-sim-complex

create very complex network environment:

    tun:   dev1 dev2 dev3 dev4   dev5 dev6 dev7 dev8
            |    |    |    |      |    |    |    |
            ------    ------      ------    ------
    bond    bond1      bond2       bond3     bond4
              |          |           |         |
              ------------           -----------
    bridge      bridge1                bridge2
                   |                      |
            --------------         --------------
    vlans  vlan1   vlan2 |        vlan3   vlan4 |
                     ----------            ----------
    aliases        alias1  alias2         alias3  alias4

parameters enables various numbers for devices:
     init-sim-complex BOND BRIDGE DEVICES ALIASES VLANS 

=cut

init-sim-complex() {

    local BOND=$1
    test -z "$BOND" && BOND=1
    local BRIDGE=$2
    test -z "$BRIDGE" && BRIDGE=1
    local TUNS=$3
    test -z "$TUNS" && TUNS=1
    local ALIASES=$4
    test -z "$ALIASES" && ALIASES=1
    local VLANS=$5
    test -z "$VLANS" && VLANS=1
    local PREFIXNAME=$initPREFIX

local FFN="slave"
DEFETH=`init-DefaultEth`

for BRID in `seq $BRIDGE`;do 
  FILLBR=`init-ifcfg-simple ${PREFIXNAME}${BRID} |tail -1`
  echo "TYPE=Bridge" >> $FILLBR
  for BND in `seq $BOND`; do

    FILLBO=`init-ifcfg-simple ${PREFIXNAME}${BRID}bnd${BND} |tail -1`
    echo "BRIDGE=${PREFIXNAME}$BRID
BONDING_OPTS='mode=1'" >> $FILLBO

    for TNS in `seq $TUNS`; do
      $initSIMULATION ${PREFIXNAME}${BRID}bnd${BND}$FFN$TNS
      FILLTNS=`init-ifcfg-simple ${PREFIXNAME}${BRID}bnd${BND}$FFN$TNS |tail -1`
      echo "MASTER=${PREFIXNAME}${BRID}bnd$BND
SLAVE=yes" >> $FILLTNS
    done
    rlRun "ifup ${PREFIXNAME}${BRID}bnd${BND}"
  done
  rlRun "ifup ${PREFIXNAME}${BRID}"

  for VLAN in `seq $VLANS`; do
    FILLVL=`init-ifcfg-simple ${PREFIXNAME}$BRID.$VLAN static 127.$VLAN.0.$VLAN |tail -1`
    echo "VLAN=yes" >> $FILLVL
  rlRun "ifup ${PREFIXNAME}$BRID.$VLAN"
  done

  for ALIAS in `seq $ALIASES`; do
    FILLAL=`init-ifcfg-simple ${PREFIXNAME}$BRID:$ALIAS static 127.0.$ALIAS.1 |tail -1`
  rlRun "ifup ${PREFIXNAME}$BRID:$ALIAS"
  done
done
}

true <<'=cut'
=pod

=head2 init-sim-complex-cleaup

remove very complex network environment

=cut

init-sim-complex-cleanup(){
    FFN="slave"
    for foo in `ls /etc/sysconfig/network-scripts/ifcfg-${$initPREFIX}*`; do
        DEV=`echo $foo |cut -d / -f 5 |sed 's/ifcfg-//'`
        sleep 1
        echo $DEV
        ifdown $DEV
        if echo $DEV | grep $FFN ; then
            $initSIMULATION-cleanup $DEV
        fi
    done
    rmmod bonding
    /bin/rm -f /etc/sysconfig/network-scripts/ifcfg-${$iPREFIX}*
    rlServiceRestore network
}



# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Verification
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   This is a verification callback which will be called by
#   rlImport after sourcing the library to make sure everything is
#   all right. It makes sense to perform a basic sanity test and
#   check that all required packages are installed. The function
#   should return 0 only when the library is ready to serve.

initLibraryLoaded() {
    if rpm=$(rpm -q initscripts); then
        rlLogDebug "Library initscripts/basic running with $rpm"
        return 0
    else
        rlLogError "Package initscripts not installed"
#this library is used also in non initscript rhel, like rhel9. Great.
        return 0
    fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Authors
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 AUTHORS

=over

=item *

Jan Scotka <jscotka@redhat.com>

=back

=cut


