# Create environment variables
echo "Criando variaveis de ambiente"
ES_USER="elasticsearch"
ES_GROUP="$ES_USER"
ES_HOME="/opt/es/elasticsearch"
ES_CLUSTER="elasticbus"
ES_WORKING_PATH="/opt/es"
ES_DATA_PATH="$ES_WORKING_PATH/data"
ES_BIN="$ES_HOME/bin/elasticsearch"
ES_LOG_PATH="$ES_WORKING_PATH/logs"
ES_CONF_PATH="$ES_WORKING_PATH/conf"
ES_TMP_PATH="$ES_WORKING_PATH/tmp"
PID_DIR="$ES_LOG_PATH"
SYSTEMD_DIR="/usr/lib/systemd/system"
ES_HEAP_SIZE=4g
ES_MAX_OPEN_FILES=32000
ES_MEMLOCK=unlimited
ES_FILENAME="elasticsearch-6.3.2.tar.gz"
ES_DIRNAME="elasticsearch-6.3.2"
VG="vgES"
LVOL="els_lv"
FS_TUNING="ext4 defaults,noatime,nodiratime,discard 0 0"
MASTER_01="server01"
MASTER_02="server02"
MASTER_03="server03"

# Add group and user (creating the homedir)
echo "Add user: $ES_USER"
sudo useradd -c "Usuario ElasticSearch" -u 1320 -g 1320 -U -m $ES_USER

# Creating Elasticsearch Home
sudo mkdir -p $ES_WORKING_PATH

# Add LVOL to FSTAB and MOUNT Filesystem
sudo sh -c "echo '/dev/mapper/$VG-$LVOL   $ES_WORKING_PATH  $FS_TUNING' >> /etc/fstab"
sudo mount -a

# Creating directories
echo "Create Elasticsearch data log and home directories"
sudo mkdir -p $ES_DATA_PATH $ES_LOG_PATH $ES_CONF_PATH $ES_TMP_PATH

# Bump max open files & unlimiting memlock for the user elasticsearch
sudo sh -c "echo '$ES_USER soft nofile $ES_MAX_OPEN_FILES' >> /etc/security/limits.d/99-elasticsearch.conf"
sudo sh -c "echo '$ES_USER hard nofile $ES_MAX_OPEN_FILES' >> /etc/security/limits.d/99-elasticsearch.conf"
sudo sh -c "echo '$ES_USER soft memlock $ES_MEMLOCK' >> /etc/security/limits.d/99-elasticsearch.conf"
sudo sh -c "echo '$ES_USER hard memlock $ES_MEMLOCK' >> /etc/security/limits.d/99-elasticsearch.conf"

# Installing JDK 8
echo "Install JDK"
yum install java-1.8.0-openjdk.x86_64 -y; update-alternatives --config java;

# Installing Elasticsearch 6.3.2
echo "Downloading elasticsearch"
wget https://artifacts.elastic.co/downloads/elasticsearch/$ES_FILENAME --directory-prefix=/tmp
cd /tmp
tar fxvz /tmp/$ES_FILENAME
sudo mv /tmp/$ES_DIRNAME $ES_WORKING_PATH
sudo ln -s $ES_WORKING_PATH/$ES_DIRNAME $ES_WORKING_PATH/elasticsearch
sudo cp -p $ES_WORKING_PATH/elasticsearch/config/* $ES_CONF_PATH
sudo rm -rf /tmp/$ES_FILENAME

# Change parameters

sed -i "s|es-home|${ES_HOME}|g" ./elasticsearch.service
sed -i "s|es-path-conf|${ES_CONF_PATH}|g" ./elasticsearch.service
sed -i "s|es-pid-dir|${PID_DIR}|g" ./elasticsearch.service
sed -i "s|working-dir|${ES_WORKING_PATH}|g" ./elasticsearch.service
sed -i "s|bin-elasticsearch|${ES_BIN}|g" ./elasticsearch.service
sudo mv ./elasticsearch.service $SYSTEMD_DIR/elasticsearch.service
sudo chown root: $SYSTEMD_DIR/elasticsearch.service
sudo systemctl enable elasticsearch.service

## Create and active TUNED profile
sudo mkdir /usr/lib/tuned/elasticsearch
sudo mv ./tuned-elasticsearch.conf /usr/lib/tuned/elasticsearch/tuned.conf
sudo tuned-adm profile elasticsearch
sudo mv ./00-system.conf.paas ./lib/sysctl.d/00-system.conf
sudo sysctl -p

## Tune Elasticsearch with 3 masters
for NUM in 1 2 3;do
cat << EOF > $ES_CONF_PATH/elasticsearch.yml
discovery.zen.ping.unicast.hosts: ['$MASTER_01:9300', '$MASTER_02:9300', '$MASTER_03:9300']
bootstrap.memory_lock: true
indices.query.bool.max_clause_count: 40960
cluster.name: $ES_CLUSTER
node.name: master_\${HOSTNAME%%.*}_${NUM}
node.data: false
node.master: true
transport.tcp.port: 930${NUM}
path.data: $ES_DATA_PATH
path.logs: $ES_LOG_PATH
http.enabled: false
gateway.expected_nodes: 1
gateway.recover_after_time: 3m
gateway.recover_after_nodes: 1
discovery.zen.minimum_master_nodes: 2
http.max_initial_line_length:  512kb
transport.host: ${HOSTNAME}
network.host: ${HOSTNAME}
thread_pool.bulk.size: 9
thread_pool.bulk.queue_size: 360
thread_pool.index.size: 9
thread_pool.index.queue_size: 360
thread_pool.search.size: 100
thread_pool.search.queue_size: 120
indices.fielddata.cache.size: 60%
#Compactacao
index.codec: best_compression
EOF
done

# Tune JVM.OPTIONS
sed -i "s|dirtmp|${ES_TMP_PATH}|g" ./jvm.options
sed -i "s|JHEAP|${ES_HEAP_SIZE}|g" ./jvm.options
sudo mv ./jvm.options.paas $ES_CONF_PATH/jvm.options

echo "Fix permissions"
sudo chown -R $ES_USER:$ES_GROUP $ES_WORKING_PATH

sudo systemctl start elasticsearch.service


