#!/bin/bash -x

#add mirrors to repo
sudo sed -i -e "s|mirrorlist=|#mirrorlist=|g" /etc/yum.repos.d/CentOS-*
sudo sed -i -e "s|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g" /etc/yum.repos.d/CentOS-*

cat <<EOF > /etc/sysconfig/watchlog
# Configuration file for my watchlog service
# Place it to /etc/sysconfig

# File and word in that file that we will be monit
WORD="ALERT"
LOG=/var/log/watchlog.log
EOF

echo "ALERT test log message" > /var/log/watchlog.log

cat <<EOF > /opt/watchlog.sh
#!/bin/bash

WORD=\$1
LOG=\$2
DATE=

if grep \$WORD \$LOG &> /dev/null
then
logger "\$DATE: I found word, Master!"
else
exit 0
fi
EOF

sed -i -e 's/DATE=/DATE=`date`/g' /opt/watchlog.sh

chmod +x /opt/watchlog.sh

cat <<EOF > /etc/systemd/system/watchlog.service
[Unit]
Description=My watchlog service

[Service]
Type=oneshot
EnvironmentFile=/etc/sysconfig/watchlog
ExecStart=/opt/watchlog.sh \$WORD \$LOG
EOF

cat <<EOF > /etc/systemd/system/watchlog.timer
[Unit]
Description=Run watchlog script every 30 second

[Timer]
# Run every 30 second
OnUnitActiveSec=30
Unit=watchlog.service

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start watchlog.timer
systemctl start watchlog.service
systemctl enable watchlog.timer
systemctl status watchlog.service

yum install -y epel-release && yum install -y spawn-fcgi php php-cli

cat <<EOF > /etc/sysconfig/spawn-fcgi
SOCKET=/var/run/php-fcgi.sock
OPTIONS="-u apache -g apache -s \$SOCKET -S -M 0600 -C 32 -F 1 -- /usr/bin/php-cgi"
EOF

cat <<EOF > /etc/systemd/system/spawn-fcgi.service
[Unit]
Description=Spawn-fcgi startup service by Otus
After=network.target

[Service]
Type=simple
PIDFile=/var/run/spawn-fcgi.pid
EnvironmentFile=/etc/sysconfig/spawn-fcgi
ExecStart=/usr/bin/spawn-fcgi -n \$OPTIONS
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon reload
systemctl start spawn-fcgi
systemctl status spawn-fcgi

cat <<EOF > /usr/lib/systemd/system/httpd.service
[Unit]
Description=The Apache HTTP Server
Wants=httpd-init.service
After=network.target remote-fs.target nss-lookup.target httpd-init.service
Documentation=man:httpd.service(8)

[Service]
Type=notify
Environment=LANG=C
EnvironmentFile=/etc/sysconfig/httpd-%I
ExecStart=/usr/sbin/httpd \$OPTIONS -DFOREGROUND
ExecReload=/usr/sbin/httpd \$OPTIONS -k graceful
# Send SIGWINCH for graceful stop
KillSignal=SIGWINCH
KillMode=mixed
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/sysconfig/httpd-first
# /etc/sysconfig/httpd-first
OPTIONS=-f conf/first.conf
EOF

cat <<EOF > /etc/sysconfig/httpd-second
# /etc/sysconfig/httpd-second
OPTIONS=-f conf/second.conf
EOF

cp /etc/httpd/conf/httpd.conf /etc/httpd/conf/first.conf
cp /etc/httpd/conf/httpd.conf /etc/httpd/conf/second.conf
sed -i -e 's/Listen 80/Listen 8080/g' /etc/httpd/conf/second.conf
sed -i -e '35 s/^/PidFile \/var\/run\/httpd-second.pid\n/;' /etc/httpd/conf/second.conf

httpd -t
systemctl daemon-reload
systemctl start httpd@first
systemctl start httpd@second
systemctl status httpd@first
systemctl status httpd@second
ss -tnulp | grep httpd

sleep 60

cat /var/log/messages | grep "I found word"
