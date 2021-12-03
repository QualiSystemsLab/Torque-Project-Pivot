#!/bin/bash
echo '=============== Staring init script for Promotions Manager API ==============='

# save all env for debugging
printenv > /var/log/colony-vars-"$(basename "$BASH_SOURCE" .sh)".txt

echo '==> Installing Node.js and NPM'
sudo apt-get update
sudo apt install curl -y
curl -sL https://deb.nodesource.com/setup_10.x | sudo bash -
apt install nodejs

echo '==> Extract api artifact to /var/promotions-manager-api'
mkdir $ARTIFACTS_PATH/drop
tar -xvf $ARTIFACTS_PATH/promotions-manager-api.*.tar.gz -C $ARTIFACTS_PATH/drop/
mkdir /var/promotions-manager-api/
tar -xvf $ARTIFACTS_PATH/drop/drop/promotions-manager-api.*.tar.gz -C /var/promotions-manager-api

echo '==> Set the DATABASE_HOST env var to be globally available to all'
echo "RDS Value:"
echo $RDS
if [ $RDS = "true" ]
then
    DATABASE_HOST=$DATABASE_HOST
else
    DATABASE_HOST=$DATABASE_HOST.$DOMAIN_NAME
fi
echo 'RDS='$RDS >> /etc/environment
echo 'DATABASE_HOST='$DATABASE_HOST >> /etc/environment
echo 'RELEASE_NUMBER='$RELEASE_NUMBER >> /etc/environment
echo 'API_BUILD_NUMBER='$API_BUILD_NUMBER >> /etc/environment
echo 'API_PORT='$API_PORT >> /etc/environment
source /etc/environment

echo '==> Install PM2, it provides an easy way to manage and daemonize nodejs applications'
npm install -g pm2

echo '==> Start our api and configure as a daemon using pm2'
cd /var/promotions-manager-api
pm2 start /var/promotions-manager-api/index.js
pm2 save
chattr +i /root/.pm2/dump.pm2
sudo su -c "env PATH=$PATH:/home/unitech/.nvm/versions/node/v4.3/bin pm2 startup systemd -u root --hp /root"


PASSWORD="$PASS"
DB="promo-manager"
OS=`cat /etc/os-release`

# install mongoimport cli tool
echo 'Install MongoDB'
apt-get update -y
apt-get install gnupg -y
wget -qO - https://www.mongodb.org/static/pgp/server-5.0.asc | apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/5.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-5.0.list
apt-get update -y
apt-get install -y mongodb
echo "mongodb-org hold" | dpkg --set-selections
echo "mongodb-org-server hold" | dpkg --set-selections
echo "mongodb-org-shell hold" | dpkg --set-selections
echo "mongodb-org-mongos hold" | dpkg --set-selections
echo "mongodb-org-tools hold" | dpkg --set-selections

# dump inputs
echo "Enpoint: $ENDPOINT"
echo "User: $USER"
echo "Password: ****"
echo "DB Name: $DB"
echo "Collection Name: $COLLECTION"
echo "Data: $DATA"

echo $OS

# wait until cluster endpoint is listining
apt-get install netcat -y
timeout=600
wait_interval=5
for (( c=0 ; c<$timeout ; c=c+$wait_interval ))	
do
    # check if enpoint is listening
    nc -z -w1 $ENDPOINT 27017
    status=$?
    if [ $status -ne 0 ]; then
        # not listening yet, waiting
        let remaining=$wait_sec-$c
        echo "Endpoint $ENDPOINT is not listening on port 27017 yet, sleeping for $wait_interval. Remaining timeout is $remaining seconds."
        unset status  # reset the $status var
        
        sleep $wait_interval
    else
        # listening, exit loop
        echo "Endpoint is listening on port 27017, exiting wait loop"
        break
    fi
done

# load data to mongodb endpoint
echo "$DATA" | mongoimport -h $ENDPOINT -u $USER -p $PASSWORD -d $DB -c $COLLECTION --jsonArray

retVal=$?
if [ $retVal -ne 0 ]; then
    echo "Error importing data"
else
    echo "Imported data successfully"
fi
exit $retVal