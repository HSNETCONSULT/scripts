#!/bin/bash

# Script de Instalação LibreNMS - HSNET CONSULTORIA
# Autor: Abraão Barbosa
# Nome: hsnet-monitoramento-script01.sh

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
    echo -e "${AZUL}                Autor: Abraão Barbosa                            ${NC}"
    echo -e "${CIANO}#################################################################${NC}"
    echo
}

exibir_banner

# Sair em caso de erro
set -e

# Captura automática do IP da máquina
IP_AUTOMATICO=$(hostname -I | awk '{print $1}')
echo -e "${AMARELO}>>> IP detectado automaticamente: ${VERDE}$IP_AUTOMATICO${NC}"
echo

# Solicitação de senha em Português - Ajustado para garantir que espere a digitação
echo -e "${AZUL}Configuração do Banco de Dados:${NC}"
# Usamos </dev/tty para garantir que o read leia do teclado mesmo se rodar via pipe
read -sp "Digite a senha do banco de dados MySQL para o usuário librenms: " DATABASEPASSWORD </dev/tty
echo
if [ -z "$DATABASEPASSWORD" ]; then
    echo -e "${VERMELHO}Erro: A senha não pode ser vazia. Por favor, execute o script novamente.${NC}"
    exit 1
fi
echo -e "${VERDE}Senha configurada com sucesso!${NC}"
echo

# Usar o IP detectado como hostname padrão, mas permitir alteração
read -p "Digite o hostname do servidor web (Padrão: $IP_AUTOMATICO): " WEBSERVERHOSTNAME </dev/tty
WEBSERVERHOSTNAME=${WEBSERVERHOSTNAME:-$IP_AUTOMATICO}

echo
echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}       Instalando pacotes necessários            ${NC}"
echo -e "${MAGENTA}#################################################${NC}"
echo

apt update
apt install -y acl curl fping git graphviz imagemagick mariadb-client mariadb-server mtr-tiny nginx-full nmap php-cli php-curl php-fpm php-gd php-gmp php-json php-mbstring php-mysql php-snmp php-xml php-zip rrdtool snmp snmpd unzip python3-command-runner python3-pymysql python3-dotenv python3-redis python3-setuptools python3-psutil python3-systemd python3-pip whois traceroute iputils-ping tcpdump vim cron

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

su - librenms -c "/opt/librenms/scripts/composer_wrapper.php install --no-dev"

echo
echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}           Configurando fuso horário             ${NC}"
echo -e "${MAGENTA}#################################################${NC}"

# Ajustando para o fuso horário do Brasil (America/Sao_Paulo) como padrão
TIMEZONE="America/Sao_Paulo"
sed -i "s|;date.timezone =|date.timezone = $TIMEZONE|" /etc/php/8.3/fpm/php.ini
sed -i "s|;date.timezone =|date.timezone = $TIMEZONE|" /etc/php/8.3/cli/php.ini
timedatectl set-timezone $TIMEZONE

echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}         Configurando MariaDB (MySQL)            ${NC}"
echo -e "${MAGENTA}#################################################${NC}"
echo

if ! grep -q "innodb_file_per_table=1" /etc/mysql/mariadb.conf.d/50-server.cnf; then
    sed -i '/\[mysqld\]/a \
innodb_file_per_table=1 \
lower_case_table_names=0' /etc/mysql/mariadb.conf.d/50-server.cnf
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

if [ ! -f /etc/php/8.3/fpm/pool.d/librenms.conf ]; then
    cp /etc/php/8.3/fpm/pool.d/www.conf /etc/php/8.3/fpm/pool.d/librenms.conf
    sed -i 's/user = www-data/user = librenms/' /etc/php/8.3/fpm/pool.d/librenms.conf
    sed -i 's/group = www-data/group = librenms/' /etc/php/8.3/fpm/pool.d/librenms.conf
    sed -i 's/\[www\]/\[librenms\]/' /etc/php/8.3/fpm/pool.d/librenms.conf
    sed -i 's|listen = /run/php/php8.3-fpm.sock|listen = /run/php-fpm-librenms.sock|' /etc/php/8.3/fpm/pool.d/librenms.conf
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
systemctl restart php8.3-fpm

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

sed -i "s/#DB_HOST=/DB_HOST=localhost/" /opt/librenms/.env
sed -i "s/#DB_DATABASE=/DB_DATABASE=librenms/" /opt/librenms/.env
sed -i "s/#DB_USERNAME=/DB_USERNAME=librenms/" /opt/librenms/.env
sed -i "s/#DB_PASSWORD=/DB_PASSWORD=$DATABASEPASSWORD/" /opt/librenms/.env
# Configura a APP_URL para evitar erros de navegação (como na logo)
sed -i "s|#APP_URL=|APP_URL=http://$WEBSERVERHOSTNAME|" /opt/librenms/.env

echo
echo -e "${MAGENTA}#################################################${NC}"
echo -e "${MAGENTA}         Corrigindo permissões de log            ${NC}"
echo -e "${MAGENTA}#################################################${NC}"
echo

# Tenta corrigir a permissão se o arquivo existir, senão aguarda um pouco
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
echo -e "${AZUL}HSNET CONSULTORIA - Soluções em Monitoramento${NC}"
echo

# --- NOVA SEÇÃO DE LIMPEZA ---
echo -e "${AMARELO}Realizando limpeza final...${NC}"

# Limpa o cache do apt
apt-get clean

# Remove o próprio script se ele estiver na pasta /tmp
if [[ "$0" == "/tmp/"* ]]; then
    echo -e "${VERDE}Removendo script temporário de instalação...${NC}"
    rm -f "$0"
fi

# Limpa o histórico de comandos do shell atual
history -c
# Limpa o arquivo de histórico para que os comandos desta sessão não sejam salvos
cat /dev/null > ~/.bash_history

echo -e "${VERDE}Limpeza concluída!${NC}"

exit 0
