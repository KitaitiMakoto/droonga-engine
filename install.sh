# Copyright (C) 2014 Droonga Project
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License version 2.1 as published by the Free Software Foundation.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

# Usage:
#
#  Ubuntu:
#
#   Install a release version:
#     $ curl https://raw.githubusercontent.com/droonga/droonga-engine/master/install.sh | sudo bash
#   Install the latest revision from the repository:
#     $ curl https://raw.githubusercontent.com/droonga/droonga-engine/master/install.sh | sudo VERSION=master bash
#   Install without prompt for the hostname:
#     $ curl https://raw.githubusercontent.com/droonga/droonga-engine/master/install.sh | sudo HOST=xxx.xxx.xxx.xxx bash
#
#  CentOS 7:
#
#   Install a release version:
#     # curl https://raw.githubusercontent.com/droonga/droonga-engine/master/install.sh | bash
#   Install the latest revision from the repository:
#     # curl https://raw.githubusercontent.com/droonga/droonga-engine/master/install.sh | VERSION=master bash
#   Install without prompt for the hostname:
#     # curl https://raw.githubusercontent.com/droonga/droonga-engine/master/install.sh | HOST=xxx.xxx.xxx.xxx bash

NAME=droonga-engine
SCRIPT_URL=https://raw.githubusercontent.com/droonga/$NAME/master/install
REPOSITORY_URL=https://github.com/droonga/$NAME.git
USER=$NAME
DROONGA_BASE_DIR=/home/$USER/droonga

: ${VERSION:=release}
: ${HOST:=Auto Detect}

case $(uname) in
  Darwin|*BSD|CYGWIN*) sed="sed -E" ;;
  *)                   sed="sed -r" ;;
esac

exist_command() {
  type "$1" > /dev/null 2>&1
}

exist_user() {
  id "$1" > /dev/null 2>&1
}

prepare_user() {
  if ! exist_user $USER; then
    echo ""
    echo "Preparing the user..."
    useradd -m $USER
  fi
}

setup_configuration_directory() {
  PLATFORM=$1

  echo ""
  echo "Setting up the configuration directory..."

  [ ! -e $DROONGA_BASE_DIR ] &&
    mkdir $DROONGA_BASE_DIR

  if [ ! -e $DROONGA_BASE_DIR/catalog.json -o \
       ! -e $DROONGA_BASE_DIR/$NAME.yaml ]; then
    [ "$HOST" = "Auto Detect" ] &&
      determine_hostname \
        "Enter a host name or an IP address which is accessible from other nodes for this node" &&
      HOST=$DETERMINED_HOSTNAME
  fi
  echo "This node is configured with a hostname $HOST."

  [ ! -e $DROONGA_BASE_DIR/catalog.json ] &&
    droonga-engine-catalog-generate --hosts=$HOST \
                                    --output=$DROONGA_BASE_DIR/catalog.json

  config_file="$DROONGA_BASE_DIR/$NAME.yaml"
  if [ ! -e $config_file ]; then
    curl -o $config_file.template $SCRIPT_URL/$PLATFORM/$NAME.yaml
    cat $config_file.template | \
      $sed -e "s/\\\$hostname/$HOST/" \
      > $config_file
    rm $config_file.template
  fi

  chown -R $USER.$USER $DROONGA_BASE_DIR
}


guess_global_hostname() {
  if hostname -d > /dev/null 2>&1; then
    domain=$(hostname -d)
    hostname=$(hostname -s)
    if [ "$domain" != "" ]; then
      echo "$hostname.$domain"
      return 0
    fi
  fi
  echo ""
  return 1
}

determine_hostname() {
  prompt_for_manual_input="$1"

  global_hostname=$(guess_global_hostname)
  if [ "$global_hostname" != "" ]; then
    DETERMINED_HOSTNAME="$global_hostname"
    return 0
  fi

  address=$(hostname -i | \
            $sed -e "s/127\.[0-9]+\.[0-9]+\.[0-9]+//g" \
                 -e "s/  +/ /g" \
                 -e "s/^ +| +\$//g" |\
            cut -d " " -f 1)
  if [ "$address" != "" ]; then
    DETERMINED_HOSTNAME="$address"
    return 0
  fi

  input_hostname "$prompt_for_manual_input" &&
    DETERMINED_HOSTNAME="$TYPED_HOSTNAME"

  return 0
}

input_hostname() {
  prompt="$1: "
  while read -p "$prompt" TYPED_HOSTNAME </dev/tty; do
    if [ "$TYPED_HOSTNAME" != "" ]; then break; fi
  done
  return 0
}


install_rroonga() {
  # Install Rroonga globally from a public gem, because custom build
  # doesn't work as we expect for Droonga...
  if exist_command grndump; then
    current_version=$(grndump -v | cut -d " " -f 2)
    version_matcher=$(cat $NAME.gemspec | \
                      grep rroonga | \
                      cut -d "," -f 2 | \
                      cut -d '"' -f 2)
    compared_version=$(echo "$version_matcher" | \
                       cut -d " " -f 2)
    operator=$(echo "$version_matcher" | cut -d " " -f 1)
    compare_result=$(ruby -e "puts('$current_version' $operator '$compared_version')")
    if [ $compare_result = "true" ]; then return 0; fi
  fi
  gem install rroonga --no-ri --no-rdoc
}

install_master() {
  gem install bundler --no-ri --no-rdoc

  [ ! -e $DROONGA_BASE_DIR ] &&
    mkdir $DROONGA_BASE_DIR

  cd $DROONGA_BASE_DIR

  if [ -d $NAME ]
  then
    cd $NAME
    install_rroonga
    git stash save
    git pull --rebase
    git stash pop
    bundle update
  else
    git clone $REPOSITORY_URL
    cd $NAME
    install_rroonga
    bundle install
  fi
  bundle exec rake build
  gem install "pkg/*.gem" --no-ri --no-rdoc
}

install_service_script() {
  INSTALL_LOCATION=$1
  PLATFORM=$2
  DOWNLOAD_URL=$SCRIPT_URL/$PLATFORM/$NAME
  if [ ! -e $INSTALL_LOCATION ]
  then
    curl -o $INSTALL_LOCATION $DOWNLOAD_URL
    chmod +x $INSTALL_LOCATION
  fi
}

install_in_debian() {
  apt-get update
  apt-get -y upgrade
  apt-get install -y ruby ruby-dev build-essential

  echo ""

  if [ "$VERSION" = "master" ]; then
    echo "Installing $NAME from the git repository..."
    apt-get install -y git
    install_master
  else
    echo "Installing $NAME from RubyGems..."
    gem install droonga-engine --no-rdoc --no-ri
  fi

  prepare_user

  setup_configuration_directory debian

  echo ""
  echo "Registering $NAME as a service..."
  install_service_script /etc/init.d/$NAME debian
  update-rc.d $NAME defaults
}

install_in_centos() {
  yum update
  yum -y groupinstall development
  yum -y install ruby-devel

  echo ""

  if [ "$VERSION" = "master" ]; then
    echo "Installing $NAME from the git repository..."
    yum -y install git
    install_master
  else
    echo "Installing $NAME from RubyGems..."
    gem install droonga-engine --no-rdoc --no-ri
  fi

  prepare_user

  setup_configuration_directory centos

  echo ""
  echo "Registering $NAME as a service..."
  install_service_script /etc/rc.d/init.d/$NAME centos
  /sbin/chkconfig --add $NAME
}

if [ -e /etc/debian_version ] || [ -e /etc/debian_release ]; then
  install_in_debian
elif [ -e /etc/centos-release ]; then
  install_in_centos
else
  echo "Not supported platform. This script works only for Debian or CentOS."
  exit 255
fi

echo ""
echo "Successfully installed $NAME."
exit 0