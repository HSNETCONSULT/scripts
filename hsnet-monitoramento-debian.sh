#!/bin/bash

# Script de Instalação LibreNMS - Adaptado para Debian (v2 Corrigida)
# Baseado no script original da HSNET CONSULTORIA
# Adaptado por: Manus AI

# Cores para o terminal
VERMELHO='\033[0;31m'
VERDE='\033[0;32m'
AMARELO='\033[1;33m'
AZUL='\033[0;34m'
MAGENTA='\033[0;35m'
CIANO='\033[0;36m'
NC='\033[0m' # Sem cor

# Função para exibir o banner
exibir_banner() {
    clear
    echo -e "${CIANO}#################################################################${NC}"
    echo -e "${AMARELO}  _    _  _____ _   _ ______ _______    _____  ____  _   _  _____ ${NC}"
    echo -e "${AMARELO} | |  | |/ ____| \ | |  ____|__   __|  / ____|/ __ \| \ | |/ ____|${NC}"
    echo -e "${AMARELO} | |__| | (___ |  \| | |__     | |    | |    | |  | |  \| | (___  ${NC}"
    echo -e "${AMARELO} |  __  |\___ \| . \` |  __|    | |    | |    | |  | | . \` |\___ \ ${NC}"
    echo -e "${AMARELO} | |  | |____) | |\  | |____   | |    | |____| |__| | |\  |____) |${NC}"
    echo -e "${AMARELO} |_|  |_|_____/|_| \_|______|  |_|     \_____|\____/|_| \_|_____/ ${NC}"
    echo -e "${CIANO}                                                                 ${NC}"
    echo -e "${VERDE}                    HSNET CONSULTORIA                            ${NC}"
    echo -e "${AZUL}                Versão Corrigida para Debian                     ${NC}"
    echo -e "${CIANO}#################################################################${NC}"
    echo
}

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
  echo -e "${VERMELHO}Erro: Este script deve ser executado como root.${NC}"
  exit 1
fi

exibir_banner

# Sair em caso de erro
set -e

# Detectar versão do Debian
DEBIAN_VERSION=$(cat /etc/debian_version | cut -d. -f1)
echo -e "${AMARELO}>>> Versão do Debian detectada: ${VERDE}$DEBIAN_VERSION${NC}"

# Adicionar repositório SURY PHP para garantir PHP 8.2+ no Debian
echo -e "${AMARELO}>>> Configurando repositório SURY PHP para garantir PHP 8.2+...${NC}"
apt update
apt install -y lsb-release apt-transport-https ca-certificates curl
curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg
echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
apt update

# Definir versão do PHP (LibreNMS exige 8.2+)
PHP_VER="8.2"
echo -e "${AMARELO}>>> Versão do PHP selecionada: ${VERDE}$PHP_VER${NC}"

# Captura automática do IP da máquina
IP_AUTOMATICO=$(hostname -I | awk '{print $1}')
echo -e "${AMARELO}>>> IP detectado automaticamente: ${VERDE}$IP_AUTOMATICO${NC}"
echo

# Solicitação de senha
echo -e "${AZUL}Configuração do Banco de Dados:${NC}"
read -sp "Digite a senha do banco de dados MySQL para o usuário librenms: " DATABASEPASSWORD </dev/tty
echo
if [ -z "$DATABASEPASSWORD" ]; then
    echo -e "${VERMELHO}Erro: A senha não pode ser vazia. Por favor, execute o script novamente.${NC}"
    exit 1
fi
echo -e "${VERDE}Senha configurada com sucesso!${NC}"
echo

# Hostname padrão
read -p "Digite o hostname do servidor web (Padrão: $IP_AUTOMATICO): " WEBSERVERHOSTNAME </dev/tty
WEBSERVERHOSTNAME=${WEBSERVERHOSTNAME:-$IP_AUTOMATICO}

echo
echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}       Instalando pacotes necessários            ${NC}"
echo -e "${MAGENTA}#################################################${NC}"
echo

apt install -y acl curl fping git graphviz imagemagick mariadb-client mariadb-server mtr-tiny nginx-full nmap \
php${PHP_VER}-cli php${PHP_VER}-curl php${PHP_VER}-fpm php${PHP_VER}-gd php${PHP_VER}-gmp php${PHP_VER}-mbstring \
php${PHP_VER}-mysql php${PHP_VER}-snmp php${PHP_VER}-xml php${PHP_VER}-zip rrdtool snmp snmpd unzip \
python3-pymysql python3-dotenv python3-redis python3-setuptools python3-psutil python3-pip \
whois traceroute iputils-ping tcpdump vim cron

# Instalação de pacotes opcionais que podem falhar
apt install -y python3-systemd || echo -e "${AMARELO}Aviso: python3-systemd não encontrado, continuando...${NC}"

echo
echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}          Criando usuário librenms               ${NC}"
echo -e "${MAGENTA}#################################################${NC}"
echo

if ! id "librenms" &>/dev/null; then
    useradd librenms -d /opt/librenms -M -r -s "$(which bash)"
fi

echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}        Clonando repositório LibreNMS            ${NC}"
echo -e "${MAGENTA}#################################################${NC}"
echo

cd /opt
if [ ! -d "/opt/librenms" ]; then
    git clone https://github.com/librenms/librenms.git
fi

echo
echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}      Configurando permissões de diretório       ${NC}"
echo -e "${MAGENTA}#################################################${NC}"
echo 

chown -R librenms:librenms /opt/librenms
chmod 771 /opt/librenms
setfacl -d -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/
setfacl -R -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/

echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}       Instalando dependências do Composer       ${NC}"
echo -e "${MAGENTA}#################################################${NC}"
echo

# Garantir que o composer use a versão correta do PHP
su - librenms -c "export PHP_BINARY=/usr/bin/php${PHP_VER}; /opt/librenms/scripts/composer_wrapper.php install --no-dev"

echo
echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}           Configurando fuso horário             ${NC}"
echo -e "${MAGENTA}#################################################${NC}"

TIMEZONE="America/Sao_Paulo"
if [ -f /etc/php/${PHP_VER}/fpm/php.ini ]; then
    sed -i "s|;date.timezone =|date.timezone = $TIMEZONE|" /etc/php/${PHP_VER}/fpm/php.ini
fi
if [ -f /etc/php/${PHP_VER}/cli/php.ini ]; then
    sed -i "s|;date.timezone =|date.timezone = $TIMEZONE|" /etc/php/${PHP_VER}/cli/php.ini
fi
timedatectl set-timezone $TIMEZONE

echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}         Configurando MariaDB (MySQL)            ${NC}"
echo -e "${MAGENTA}#################################################${NC}"
echo

MARIADB_CONF="/etc/mysql/mariadb.conf.d/50-server.cnf"
[ ! -f "$MARIADB_CONF" ] && MARIADB_CONF="/etc/mysql/my.cnf"

if ! grep -q "innodb_file_per_table=1" "$MARIADB_CONF"; then
    sed -i '/\[mysqld\]/a \
innodb_file_per_table=1 \
lower_case_table_names=0' "$MARIADB_CONF"
fi

echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}         Reiniciando serviço MariaDB             ${NC}"
echo -e "${MAGENTA}#################################################${NC}"
echo

systemctl enable mariadb
systemctl restart mariadb

echo
echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}      Criando Banco de Dados e Usuário           ${NC}"
echo -e "${MAGENTA}#################################################${NC}"

mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS librenms CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'librenms'@'localhost' IDENTIFIED BY '$DATABASEPASSWORD';
GRANT ALL PRIVILEGES ON librenms.* TO 'librenms'@'localhost';
FLUSH PRIVILEGES;
EOF

echo
echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}       Configurando PHP-FPM para LibreNMS        ${NC}"
echo -e "${MAGENTA}#################################################${NC}"

if [ ! -f /etc/php/${PHP_VER}/fpm/pool.d/librenms.conf ]; then
    cp /etc/php/${PHP_VER}/fpm/pool.d/www.conf /etc/php/${PHP_VER}/fpm/pool.d/librenms.conf
    sed -i 's/user = www-data/user = librenms/' /etc/php/${PHP_VER}/fpm/pool.d/librenms.conf
    sed -i 's/group = www-data/group = librenms/' /etc/php/${PHP_VER}/fpm/pool.d/librenms.conf
    sed -i 's/\[www\]/\[librenms\]/' /etc/php/${PHP_VER}/fpm/pool.d/librenms.conf
    sed -i "s|listen = /run/php/php${PHP_VER}-fpm.sock|listen = /run/php-fpm-librenms.sock|" /etc/php/${PHP_VER}/fpm/pool.d/librenms.conf
fi

echo
echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}          Configurando Nginx                     ${NC}"
echo -e "${MAGENTA}#################################################${NC}"

cat << EOF > /etc/nginx/conf.d/librenms.conf
server {
 listen      80;
 server_name $WEBSERVERHOSTNAME;
 root        /opt/librenms/html;
 index       index.php;

 charset utf-8;
 gzip on;
 gzip_types text/css application/javascript text/javascript application/x-javascript image/svg+xml text/plain text/xsd text/xsl text/xml image/x-icon;
 location / {
  try_files \$uri \$uri/ /index.php?\$query_string;
 }
 location ~ [^/]\.php(/|$) {
  fastcgi_pass unix:/run/php-fpm-librenms.sock;
  fastcgi_split_path_info ^(.+\.php)(/.+)$;
  include fastcgi.conf;
 }
 location ~ /\.(?!well-known).* {
  deny all;
 }
}
EOF

echo
echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}       Removendo configuração padrão Nginx       ${NC}"
echo -e "${MAGENTA}#################################################${NC}"

rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default

echo
echo -e "${AMARELO}Reiniciando Nginx e PHP-FPM...${NC}"
echo
systemctl restart nginx
systemctl restart php${PHP_VER}-fpm

echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}          Configurando comando lnms              ${NC}"
echo -e "${MAGENTA}#################################################${NC}"
echo

if [ ! -L /usr/bin/lnms ]; then
    ln -s /opt/librenms/lnms /usr/bin/lnms
fi
cp /opt/librenms/misc/lnms-completion.bash /etc/bash_completion.d/

echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}               Configurando SNMP                 ${NC}"
echo -e "${MAGENTA}#################################################${NC}"

cp /opt/librenms/snmpd.conf.example /etc/snmp/snmpd.conf
sed -i 's/RANDOMSTRINGGOESHERE/public/' /etc/snmp/snmpd.conf
curl -o /usr/bin/distro https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/distro
chmod +x /usr/bin/distro
systemctl enable snmpd
systemctl restart snmpd

cp /opt/librenms/dist/librenms.cron /etc/cron.d/librenms

echo
echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}        Configurando agendador LibreNMS          ${NC}"
echo -e "${MAGENTA}#################################################${NC}"
echo

cp /opt/librenms/dist/librenms-scheduler.service /opt/librenms/dist/librenms-scheduler.timer /etc/systemd/system/
systemctl enable librenms-scheduler.timer
systemctl start librenms-scheduler.timer

echo
echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}          Configurando logrotate                 ${NC}"
echo -e "${MAGENTA}#################################################${NC}"

cp /opt/librenms/misc/librenms.logrotate /etc/logrotate.d/librenms

echo
echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}        Instalando e configurando syslog-ng      ${NC}"
echo -e "${MAGENTA}#################################################${NC}"
echo
apt-get install -y syslog-ng-core
cat << 'EOF' > /etc/syslog-ng/conf.d/librenms.conf
source s_net {
        tcp(port(514) flags(syslog-protocol));
        udp(port(514) flags(syslog-protocol));
};

destination d_librenms {
        program("/opt/librenms/syslog.php" template ("$HOST||$FACILITY||$PRIORITY||$LEVEL||$TAG||$R_YEAR-$R_MONTH-$R_DAY $R_HOUR:$R_MIN:$R_SEC||$MSG||$PROGRAM\n") template-escape(yes));
};

log {
        source(s_net);
        source(s_src);
        destination(d_librenms);
};
EOF

chown librenms:librenms /opt/librenms/syslog.php
chmod +x /opt/librenms/syslog.php

echo -e "${AMARELO}Reiniciando syslog-ng...${NC}"
systemctl restart syslog-ng

echo
echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}            Ajustando arquivo .env               ${NC}"
echo -e "${MAGENTA}#################################################${NC}"

if [ ! -f /opt/librenms/.env ]; then
    cp /opt/librenms/.env.example /opt/librenms/.env
    chown librenms:librenms /opt/librenms/.env
fi

sed -i "s/#DB_HOST=/DB_HOST=localhost/" /opt/librenms/.env
sed -i "s/#DB_DATABASE=/DB_DATABASE=librenms/" /opt/librenms/.env
sed -i "s/#DB_USERNAME=/DB_USERNAME=librenms/" /opt/librenms/.env
sed -i "s/#DB_PASSWORD=/DB_PASSWORD=$DATABASEPASSWORD/" /opt/librenms/.env
sed -i "s|#APP_URL=|APP_URL=http://$WEBSERVERHOSTNAME|" /opt/librenms/.env

echo -e "${MAGENTA}         Corrigindo permissões de log            ${NC}"
echo -e "${MAGENTA}#################################################${NC}"
echo

if [ -f /opt/librenms/logs/librenms.log ]; then
    chown librenms:librenms /opt/librenms/logs/librenms.log
else
    echo -e "${AMARELO}Aguardando o arquivo de log aparecer para ajustar permissões...${NC}"
    sleep 2
    [ -f /opt/librenms/logs/librenms.log ] && chown librenms:librenms /opt/librenms/logs/librenms.log
fi

echo
echo -e "${VERDE}#################################################################${NC}"
echo -e "${VERDE}   Instalação e configuração do LibreNMS concluída com sucesso!  ${NC}"
echo -e "${VERDE}#################################################################${NC}"
echo
echo -e "${AMARELO}Próximos passos:${NC}"
echo -e "1. Acesse no navegador: ${CIANO}http://$WEBSERVERHOSTNAME${NC}"
echo -e "2. Complete a configuração via interface web."
echo -e "3. Após concluir a web, execute o comando abaixo para ativar o syslog:"
echo -e "${VERDE}su librenms -c \"lnms config:set enable_syslog true\"${NC}"
echo
echo -e "4. Quando um dispositivo for monitorado, valide a instalação:"
echo -e "${VERDE}su librenms -c /opt/librenms/validate.php${NC}"
echo
echo -e "5. Caso queira trocar o IP ou dominio de Acesso use esse comando:"
echo -e "${VERDE}su - librenms -c \"lnms config:set base_url http://NOVO_IP_OU_DOMINIO\"${NC}"
echo
echo -e "${AZUL}HSNET CONSULTORIA - Soluções em Monitoramento${NC}"
echo

# --- LIMPEZA FINAL ---
echo -e "${AMARELO}Realizando limpeza final...${NC}"
apt-get clean
history -c
cat /dev/null > ~/.bash_history

echo -e "${VERDE}Limpeza concluída!${NC}"

exit 0
