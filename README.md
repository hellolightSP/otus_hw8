**Systemd - создание unit-файла**

**Задание**

- Написать service, который будет раз в 30 секунд мониторить лог на предмет наличия ключевого слова (файл лога и ключевое слово должны задаваться в /etc/sysconfig или в /etc/default).
- Установить spawn-fcgi и переписать init-скрипт на unit-файл (имя service должно называться так же: spawn-fcgi).
- Дополнить unit-файл httpd (он же apache2) возможностью запустить несколько инстансов сервера с разными конфигурационными файлами.

**Выполнение:**

**Скрипт с выполнением ДЗ, и вывод всех команд в приложенных файлах: 
[systemd.sh](https://github.com/hellolightSP/otus_hw8/blob/main/systemd.sh),
[otus_hw7_systemd](https://github.com/hellolightSP/otus_hw8/blob/main/otus_hw7_systemd)**


Добавляю источник репозиториев для Centos 8, с mirrors по умолчанию ничего не устанавливается 
```
sudo sed -i -e "s|mirrorlist=|#mirrorlist=|g" /etc/yum.repos.d/CentOS-*
sudo sed -i -e "s|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g" /etc/yum.repos.d/CentOS-*
```

**Написать service, который будет раз в 30 секунд мониторить лог на предмет наличия ключевого слова (файл лога и ключевое слово должны задаваться в /etc/sysconfig или в /etc/default).**

```
#Редактируем /etc/sysconfig/ для watchlog.service

cat <<EOF > /etc/sysconfig/watchlog
# Configuration file for my watchlog service
# Place it to /etc/sysconfig
# File and word in that file that we will be monit
WORD="ALERT"
LOG=/var/log/watchlog.log
EOF

#Добавляем тестовое сообщение в /var/log/watchlog.log

echo "ALERT test log message" > /var/log/watchlog.log

#Пишем проверочный скрипт

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

# Для выставления даты пришлось воспользоваться sed, т.к. через EOF в переменную DATE подставляется сразу текущая дата

sed -i -e 's/DATE=/DATE=`date`/g' /opt/watchlog.sh

chmod +x /opt/watchlog.sh

#Cоздаем сервис watchlog.service

cat <<EOF > /etc/systemd/system/watchlog.service
[Unit]
Description=My watchlog service
[Service]
Type=oneshot
EnvironmentFile=/etc/sysconfig/watchlog
ExecStart=/opt/watchlog.sh \$WORD \$LOG
EOF

#Cоздаем таймер watchlog.timer

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

# Перезагружаем, проверяем статус сервиса\таймера, для старта работы таймера нужно 1 раз запустить сервис, далее таймер сам его включает\выключает. Без запуска сервиса, таймер у меня не заработал.

systemctl daemon-reload
systemctl start watchlog.timer
systemctl start watchlog.service
systemctl enable watchlog.timer
systemctl status watchlog.service

```

**Установить spawn-fcgi и переписать init-скрипт на unit-файл (имя service должно называться так же: spawn-fcgi).**

```
#Устанавливаем необходимые пакеты

yum install -y epel-release && yum install -y spawn-fcgi php php-cli

#Правим /etc/sysconfig/ для сервиса spawn-fcgi

cat <<EOF > /etc/sysconfig/spawn-fcgi
SOCKET=/var/run/php-fcgi.sock
OPTIONS="-u apache -g apache -s \$SOCKET -S -M 0600 -C 32 -F 1 -- /usr/bin/php-cgi"
EOF

#Создаем сервис

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

#Запускаем сервис, проверяем статус

systemctl daemon-reload
systemctl start spawn-fcgi
systemctl status spawn-fcgi
```

**Дополнить unit-файл httpd (он же apache2) возможностью запустить несколько инстансов сервера с разными конфигурационными файлами.**

```
# Правим конфиг для сервиса httpd, добавляем EnvironmentFile=/etc/sysconfig/httpd-%I

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

#Создаем /etc/sysconfig/ для новых сервисов httpd

cat <<EOF > /etc/sysconfig/httpd-first
# /etc/sysconfig/httpd-first
OPTIONS=-f conf/first.conf
EOF

cat <<EOF > /etc/sysconfig/httpd-second
# /etc/sysconfig/httpd-second
OPTIONS=-f conf/second.conf
EOF

# Правим /etc/httpd/conf/   для first и second сервисов 

cp /etc/httpd/conf/httpd.conf /etc/httpd/conf/first.conf
cp /etc/httpd/conf/httpd.conf /etc/httpd/conf/second.conf
sed -i -e 's/Listen 80/Listen 8080/g' /etc/httpd/conf/second.conf
sed -i -e '35 s/^/PidFile \/var\/run\/httpd-second.pid\n/;' /etc/httpd/conf/second.conf

#Проверяем конфиги httpd, стартуем сервисы, проверяем статусы

httpd -t
systemctl daemon-reload
systemctl start httpd@first
systemctl start httpd@second
systemctl status httpd@first
systemctl status httpd@second
ss -tnulp | grep httpd

#Пауза, что бы пособирались логи из 1 задания

sleep 60

#Проверяем что сервис watchlog.service запускается по таймеру

cat /var/log/messages | grep "I found word"
```
