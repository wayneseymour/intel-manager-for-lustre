#!/bin/bash -ex

if [ "$slave" = "rhel6&&ssi" ]; then
    RHEL=true
else
    RHEL=false
fi

spacelist_to_commalist() {
    echo $@ | tr ' ' ','
}

[ -r localenv ] && . localenv

# Remove test results and coverage reports from previous run
rm -rfv $PWD/test_reports/*
rm -rfv $PWD/coverage_reports/.coverage*
mkdir -p $PWD/test_reports
mkdir -p $PWD/coverage_reports

ARCHIVE_NAME=ieel-1.90.0.tar.gz
CLUSTER_CONFIG=${CLUSTER_CONFIG:-"$(ls $PWD/shared_storage_configuration_cluster_cfg.json)"}
CHROMA_DIR=${CHROMA_DIR:-"$PWD/chroma/"}
USE_FENCE_XVM=false

eval $(python $CHROMA_DIR/chroma-manager/tests/utils/json_cfg2sh.py "$CLUSTER_CONFIG")

TESTS=${TESTS:-"tests/integration/installation_and_upgrade/"}
PROXY=${PROXY:-''} # Pass in a command that will set your proxy settings iff the cluster is behind a proxy. Ex: PROXY="http_proxy=foo https_proxy=foo"


trap "set +e; echo 'Collecting reports...'; scp root@$TEST_RUNNER:~/test_report*.xml \"$PWD/test_reports/\"" EXIT

echo "Beginning installation and setup..."

# put some keys on the nodes for easy access by developers
pdsh -l root -R ssh -S -w $(spacelist_to_commalist $ALL_NODES) "exec 2>&1; set -xe
cat <<\"EOF\" >> /root/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCrcI6x6Fv2nzJwXP5mtItOcIDVsiD0Y//LgzclhRPOT9PQ/jwhQJgrggPhYr5uIMgJ7szKTLDCNtPIXiBEkFiCf9jtGP9I6wat83r8g7tRCk7NVcMm0e0lWbidqpdqKdur9cTGSOSRMp7x4z8XB8tqs0lk3hWefQROkpojzSZE7fo/IT3WFQteMOj2yxiVZYFKJ5DvvjdN8M2Iw8UrFBUJuXv5CQ3xV66ZvIcYkth3keFk5ZjfsnDLS3N1lh1Noj8XbZFdSRC++nbWl1HfNitMRm/EBkRGVP3miWgVNfgyyaT9lzHbR8XA7td/fdE5XrTpc7Mu38PE7uuXyLcR4F7l brian@brian-laptop
EOF" | dshbak -c
if [ ${PIPESTATUS[0]} != 0 ]; then
    exit 1
fi

# need to remove the chroma repositories configured by the provisioner
pdsh -l root -R ssh -S -w $(spacelist_to_commalist $CHROMA_MANAGER ${STORAGE_APPLIANCES[@]}) "exec 2>&1; set -xe
if $RHEL; then
yum-config-manager --enable  rhel-6-server-optional-rpms
fi
if [ -f /etc/yum.repos.d/autotest.repo ]; then
    rm -f /etc/yum.repos.d/autotest.repo
fi
$PROXY yum install -y omping" | dshbak -c
if [ ${PIPESTATUS[0]} != 0 ]; then
    exit 1
fi

# Install and setup integration tests on integration test runner
scp $CLUSTER_CONFIG root@$TEST_RUNNER:/root/cluster_cfg.json
ssh root@$TEST_RUNNER <<EOF
exec 2>&1; set -xe
$PROXY yum --disablerepo=\* --enablerepo=chroma makecache
$PROXY yum -y install chroma-manager-integration-tests

if $USE_FENCE_XVM; then
    # make sure the host has fence_virtd installed and configured
    ssh root@$HOST_IP "exec 2>&1; set -xe
    uname -a
    $PROXY yum install -y fence-virt fence-virtd fence-virtd-libvirt fence-virtd-multicast
    mkdir -p /etc/cluster
    echo \"not secure\" > /etc/cluster/fence_xvm.key
    restorecon -Rv /etc/cluster/
    cat <<\"EOF1\" > /etc/fence_virt.conf
backends {
	libvirt {
		uri = \"qemu:///system\";
	}

}

listeners {
	multicast {
		port = \"1229\";
		family = \"ipv4\";
		address = \"225.0.0.12\";
		key_file = \"/etc/cluster/fence_xvm.key\";
		interface = \"virbr0\";
	}

}

fence_virtd {
	module_path = \"/usr/lib64/fence-virt\";
	backend = \"libvirt\";
	listener = \"multicast\";
}
EOF1
    chkconfig --add fence_virtd
    chkconfig fence_virtd on
    service fence_virtd restart"
fi
EOF

# Install and setup chroma software storage appliances
pdsh -l root -R ssh -S -w $(spacelist_to_commalist ${STORAGE_APPLIANCES[@]}) "exec 2>&1; set -xe
# Ensure that coverage is disabled
rm -f /usr/lib/python2.6/site-packages/sitecustomize.py*

if $USE_FENCE_XVM; then
    # fence_xvm support
    mkdir -p /etc/cluster
    echo \"not secure\" > /etc/cluster/fence_xvm.key
fi" | dshbak -c
if [ ${PIPESTATUS[0]} != 0 ]; then
    exit 1
fi

if [ -z "$JENKINS_PULL" ]; then
    JENKINS_PULL="2cf9b55238c654b00bc37a6e8ccc4caf"
fi
# first fetch and install chroma 2.0.2.0
BUILD_JOB=chroma-blessed
BUILD_NUM=62
IEEL_FROM_VERSION=$(curl -s -k -u "jenkins-pull:${JENKINS_PULL}" "${JENKINS_URL}job/$BUILD_JOB/$BUILD_NUM/arch=x86_64,distro=el6.4/api/xml?xpath=*/artifact/fileName&wrapper=foo" | sed -e 's/.*>\(ieel-.*gz\)<.*/\1/')
curl -k -O -u "jenkins-pull:${JENKINS_PULL}" "${JENKINS_URL}job/$BUILD_JOB/$BUILD_NUM/arch=x86_64,distro=el6.4/artifact/chroma-bundles/$IEEL_FROM_VERSION"

# Install and setup old chroma manager
scp $IEEL_FROM_VERSION $CHROMA_DIR/chroma-manager/tests/utils/install.exp root@$CHROMA_MANAGER:/tmp
ssh root@$CHROMA_MANAGER "#don't do this, it hangs the ssh up, when used with expect, for some reason: exec 2>&1
set -ex
yum -y install expect
# Install from the installation package
cd /tmp
tar xzvf $IEEL_FROM_VERSION
cd ${IEEL_FROM_VERSION%%.tar.gz}
if $RHEL; then
# need to hack out the repo check since it fails on EL6 in 2.0.2.0
ed << \"EOF\" install
/= _test_yum/s/,.*/ = True/
wq
EOF
fi
if ! expect ../install.exp $CHROMA_USER $CHROMA_EMAIL $CHROMA_PASS ${CHROMA_NTP_SERVER:-localhost}; then
    rc=\${PIPESTATUS[0]}
    cat /var/log/chroma/install.log
    exit \$rc
fi"
if [ ${PIPESTATUS[0]} != 0 ]; then
    exit 1
fi

echo "Create and exercise a filesystem..."

ssh root@$TEST_RUNNER "exec 2>&1; set -xe
cd /usr/share/chroma-manager/
unset http_proxy; unset https_proxy
./tests/integration/run_tests -f -c /root/cluster_cfg.json -x ~/test_report_pre_upgrade.xml $TESTS/../shared_storage_configuration/test_cluster_setup.py $TESTS/test_create_filesystem.py:TestCreateFilesystem.test_create"

echo "Now upgrade IML..."

# Install and setup chroma manager
scp $ARCHIVE_NAME $CHROMA_DIR/chroma-manager/tests/utils/upgrade.exp root@$CHROMA_MANAGER:/tmp
ssh root@$CHROMA_MANAGER "#don't do this, it hangs the ssh up, when used with expect, for some reason: exec 2>&1
set -ex
yum -y update
# Install from the installation package
cd /tmp
tar xzvf $ARCHIVE_NAME
cd $(basename $ARCHIVE_NAME .tar.gz)

echo \"First without access to YUM repos\"

ips=\$(grep -e ^base -e ^mirror /etc/yum.repos.d/* | sed -e 's/.*:\/\/\([^/]*\)\/.*/\1/g' -e 's/:.*//' | sort -u | while read n; do getent ahosts \$n | sed -ne 's/\(.*\)  STREAM .*/\1/p'; done | sort -u)
for ip in \$ips; do
    iptables -I OUTPUT -d \$ip -p tcp --dport 80 -j REJECT
done
iptables -L -nv

if expect ../upgrade.exp; then
    echo \"Installation unexpectedly succeeded without access to repos\"
    for ip in \$ips; do
        iptables -D OUTPUT -d \$ip -p tcp --dport 80 -j REJECT
    done
    exit 1
fi
for ip in \$ips; do
    if ! iptables -D OUTPUT -d \$ip -p tcp --dport 80 -j REJECT; then
        rc=\${PIPESTATUS[0]}
        iptables -L -nv
        exit \$rc
    fi
done

echo \"Now with EPEL configured\"

cat <<EOF > /etc/yum.repos.d/epel.repo
[epel]
name=epel
baseurl=http://${COBBLER_SERVER:-10.14.80.6}/cobbler/repo_mirror/EPEL-6-x86_64/
enabled=1
priority=1
gpgcheck=0
sslverify=0
EOF
yum makecache

if expect ../upgrade.exp; then
    echo \"Installation unexpectedly succeeded with EPEL configured\"
    rm -f /etc/yum.repos.d/epel.repo
    exit 1
fi
rm -f /etc/yum.repos.d/epel.repo

if $RHEL; then
# Now with the optional channel disabled
yum-config-manager --disable  rhel-6-server-optional-rpms
if expect ../upgrade.exp; then
    echo \"Installation unexpectedly succeeded with the RHEL optional channel disabled\"
    exit 1
fi
yum-config-manager --enable  rhel-6-server-optional-rpms
fi

if ! expect ../upgrade.exp; then
    rc=\${PIPESTATUS[0]}
    cat /var/log/chroma/install.log
    exit \$rc
fi
# install cman here to test that the fence-agents-iml package is being a
# "duck-like" replacement for fence-agents since cman depends on
# fence-agents
yum -y install cman

cat <<\"EOF1\" > /usr/share/chroma-manager/local_settings.py
import logging
LOG_LEVEL = logging.DEBUG
$LOCAL_SETTINGS
EOF1

# Ensure that coverage is disabled
rm -f /usr/lib/python2.6/site-packages/sitecustomize.py*"

echo "End upgrade and setup."

echo "Test existing filesystem is still there"

ssh root@$TEST_RUNNER "exec 2>&1; set -xe
cd /usr/share/chroma-manager/
unset http_proxy; unset https_proxy
./tests/integration/run_tests -f -c /root/cluster_cfg.json -x ~/test_report_post_upgrade.xml $TESTS/test_update_with_yum.py $TESTS/test_create_filesystem.py:TestExistsFilesystem.test_exists"

# test that removing the chroma-manager RPM removes /var/lib/chroma
ssh root@$CHROMA_MANAGER "set -xe
exec 2>&1
ls -l /var/lib/chroma
rpm -e chroma-manager-cli chroma-manager chroma-manager-libs
if [ -d /var/lib/chroma ]; then
    echo \"Removing RPMs failed to clean up /var/lib/chroma\"
    ls -l /var/lib/chroma
    exit 1
fi"

exit 0
