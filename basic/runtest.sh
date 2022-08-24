#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /CoreOS/initscripts/Library/basic
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

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

PACKAGE="initscripts"
PHASE=${PHASE:-Test}

rlJournalStart
    rlPhaseStartSetup
        rlRun "rlImport initscripts/basic"
    rlPhaseEnd

        
    rlPhaseStartTest "Network Namespaces"
        if rlIsRHEL ">=7"; then
            init-NM
            BRIDGENAME=br1
            init-sim-veth aaa $BRIDGENAME
            init-sim-veth bbb $BRIDGENAME
            init-netns-addif ns1 aaa
            init-netns-addif ns2 bbb
            rlRun "init-netns-execute ns1 ip a a dev aaa 192.168.222.2/24"
            rlRun "init-netns-execute ns2 ip a a dev bbb 192.168.222.3/24"
            init-netns-execute ns1 nc -l 1234 > out.log&
            rlRun "sleep 2"
            rlRun "echo hallo | init-netns-execute ns2 nc 192.168.222.2 1234"
            rlRun "sleep 2"
            rlRun "cat out.log | grep hallo"
            init-netns-cleanup ns1 aaa
            init-netns-cleanup ns2 bbb
            init-NM-cleanup
            rlRun "rm -f out.log"
        else
            rlLog "net namespaces not supported on RHEL<7"
        fi
    rlPhaseEnd
    
    rlPhaseStartTest "Create"
        init-NM
        rlRun "init-DefaultEth"
        
        init-sim-dummy dm
        rlRun "ip a s dev dm"
        init-sim-dummy-cleanup dm
        rlRun "ip a s dev dm" 1-255
        
        init-sim-tap xxx
        rlRun "ip a s dev xxx"
        init-sim-tap-cleanup xxx
        rlRun "ip a s dev xxx" 1-255
        
        init-sim-veth abc yyy
        init-sim-veth bbb yyy
        rlRun "ip a s dev abc"
        rlRun "ip a s dev yyy"
        init-dhcp abc
        rlRun "ip a s dev abc | grep $initBASE_PREFIX"
        rlRun "ip a s dev bbb | grep $initBASE_PREFIX" 1-255

        dhclient -d bbb &
        CLIENTPID=$!
        rlLog "running: `cat /proc/$CLIENTPID/cmdline`"

        rlRun "sleep 20"
        rlRun "ip a s dev bbb | grep $initBASE_PREFIX"
        rlRun "kill $CLIENTPID"
        init-sim-veth-cleanup abc
        init-sim-veth-cleanup bbb
        rlRun "ip a s dev abc" 1-255
        rlRun "ip a s dev yyy" 1-255
        rlRun "ip a"
        init-NM-cleanup
        init-dhcp-cleanup
        rlRun "ip link del br1"
    rlPhaseEnd
    
    rlPhaseStartCleanup
        rlRun "echo no cleanup"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd


