#!/bin/bash

set -e

if [ "$(id -u)" != 0 ]; then
        echo "root access required to install!"
        exit 1
fi

[ ! $(which make) ] && echo "make need to be installed" && exit 1
[ ! $(which curl) ] && echo "curl need to be installed" && exit 1
[ ! $(which git) ] && echo "git need to be installed" && exit 1

echo "Info: squirrel will be installed on your system, don't use it because it can break your system packages!"

if [ -e ./stock-packaging ]; then
  cd stock-packaging
  git pull
  make install

else
  git clone https://github.com/stock-linux/stock-packaging
  cd stock-packaging
  make install

fi

cd ..

curl -L -o config-install.sh https://github.com/stock-linux/installer/raw/0.3.0/src/config-install.sh
curl -L -o post-install.sh https://github.com/stock-linux/installer/raw/0.3.0/src/post-install.sh

chmod +x config-install.sh

./config-install.sh

