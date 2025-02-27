#! /bin/sh

# Identify & validate the OS
OS_NAME=$(cat /etc/os-release | grep '^ID=' | cut -d'=' -f2);
OS_VERSION=$(cat /etc/os-release | grep '^VERSION_ID=' | cut -d'=' -f2);

# Generate random passwords for DB
DB_NAME=jwtplus_$(tr -dc 'a-z0-9' < /dev/urandom | head -c 6);
DB_USER=jwtplususer_$(tr -dc 'a-z0-9' < /dev/urandom | head -c 6);
DB_PASS_ROOT=$(tr -dc 'A-Za-z0-9!@#$^&*-' < /dev/urandom | head -c 15);
DB_PASS_USER=$(tr -dc 'A-Za-z0-9!@#$^&*-' < /dev/urandom | head -c 13);

BINARY_NAME=jwtplus
BINARY_REMOTE=https://github.com/jwtplus/jwtplus/releases/latest/download/jwtplus-linux-amd64.tar.gz
INSTALL_FOLDER=/opt/jwtplus/
BINARY_INSTALL=$INSTALL_FOLDER$BINARY_NAME
IP_ADDRESS=0.0.0.0
APP_PORT=2025
CONFIG_FILE="jwtplus.yaml"

# Print system info
echo "-------------------------------------------------"
echo "Distro Name: $OS_NAME"
echo "Version: $OS_VERSION"
echo "-------------------------------------------------"

# Set the Server Timezone to UTC
apk add tzdata && cp /usr/share/zoneinfo/UTC /etc/localtime

# Update the system
apk update && apk upgrade

# Install firewall & common network tools
apk add iptables net-tools

# Enable firewall rules
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport $APP_PORT -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -P INPUT DROP

# Save iptables rules
rc-service iptables save

# Install MariaDB database server
apk add mariadb mariadb-client wget
rc-service mariadb setup
rc-service mariadb start
rc-update add mariadb

# Secure MySQL Installation
mariadb -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')";
mariadb -u root -e "DELETE FROM mysql.user WHERE User=''";
mariadb -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'";
mariadb -u root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$DB_PASS_ROOT')";

# Create new database and user
mariadb -u root -e "CREATE DATABASE $DB_NAME CHARACTER SET utf8 COLLATE utf8_general_ci";
mariadb -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS_USER'";
mariadb -u root -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost'";
mariadb -u root -e "FLUSH PRIVILEGES";

# Store database credentials
cat >> /root/database.txt <<EOF
------------------------------------------------
Generated by JWTPlus installation script
------------------------------------------------
Database Location: localhost
Database Port: 3306
Database Username: $DB_USER
Database Password: $DB_PASS_USER
Database Name: $DB_NAME
------------------------------------------------
Database Root Password: $DB_PASS_ROOT
------------------------------------------------
EOF

# Download & Install JWTPlus
mkdir -p $INSTALL_FOLDER
cd $INSTALL_FOLDER
wget -O jwtplus.tar.gz $BINARY_REMOTE;
tar -xzf jwtplus.tar.gz
mv jwtplus-linux-amd64/jwtplus-linux-amd64 ./jwtplus;
chmod +x jwtplus
rm -r jwtplus-linux-amd64/;
rm jwtplus.tar.gz;

# Generate JWTPlus configuration file
echo "Generating JWTPlus configuration file..."
cat <<EOF > "$CONFIG_FILE"
debug: false
server:
  ip: $IP_ADDRESS
  port: $APP_PORT
db:
  location: 127.0.0.1
  port: 3306
  username: $DB_USER
  password: $DB_PASS_USER
  dbname: $DB_NAME
EOF

# Initialize JWTPlus
echo "Loading database table and creating root key";
/opt/jwtplus/jwtplus install >> /root/root-key.txt

# Create OpenRC service for JWTPlus
cat > /etc/init.d/jwtplus <<EOF
#!/sbin/openrc-run
depend() {
    need net
    use mysql
}
command="$BINARY_INSTALL"
command_args="run"
pidfile="/run/jwtplus.pid"
name="JWTPlus"

start() {
    ebegin "Starting JWTPlus"
    start-stop-daemon --start --exec \$command -- \$command_args
    eend $?
}

stop() {
    ebegin "Stopping JWTPlus"
    start-stop-daemon --stop --exec \$command
    eend $?
}
EOF

chmod +x /etc/init.d/jwtplus
rc-update add jwtplus default
rc-service jwtplus start

# Installation Completed, Printout important details
echo "-------------------------------------------------"
echo "Installation Completed"
echo "1. Your root key can be found in /root/root-key.txt"
echo "2. Your database root password can be found in /root/database.txt"
echo "JWTPlus Service Commands:"
echo "To start: rc-service jwtplus start"
echo "To restart: rc-service jwtplus restart"
echo "To stop: rc-service jwtplus stop"
echo "-------------------------------------------------"
