#!/bin/bash

#
# Log functions
#
log(){
  echo "[${1}]: ${*:2}"
}
notice(){
  log "INFO" ${*}
}
warning(){
  log "WARNING" ${*}
}
fatal(){
  log "ERROR" ${*} "Exiting..."
  exit 1
}

#
# Maps the yaml file (Only one depth permitted)
# to the calling file
#
map_environment()
{
  local ENV_FILE="${1}"
  local PARAMETER_LIST=$(grep -v ':$' "${ENV_FILE}" | grep -v '^  - ' | cut -d ':' -f1)

  for PARAMETER in ${PARAMETER_LIST}; do
    ## Get parameter value
    local VALUE=$(grep "^${PARAMETER}:" "${ENV_FILE}" | cut -d ':' -f2 | tr -d '\040\011\012\015')
    local VAR=$(echo ${PARAMETER} | awk '{print toupper($0)}')
    export ${VAR}="${VALUE}"
  done

  . VERSIONS
}

#
# Checks the supported dists
#
supported_dists(){
  if [[ -z $(which systemctl) ]]; then
    fatal "Incorrect init system."
  fi
  if [[ ! -z $(which lsb_release) ]]; then
    if [[ $(lsb_release -i -s) != "Ubuntu" ]]; then
      fatal "Incorrect Linux Distribution."
    fi
  else
    fatal "Incorrect Linux Distribution,"
  fi
}

#
# Set up Git username, Mail and Credential cache
#
config_settings(){
  git config --global user.name "${FULL_NAME}"
  git config --global user.email "${PERSONAL_EMAIL}"
  git config --global credential.helper 'cache --timeout=3600'
  git config --global --add alias.commit "commit -S"
}

check_docker(){
  if [[ -z $(which docker) ]]; then
    fatal "Docker not installed."
  fi
  if [[ $(systemctl is-active docker) != 'active' ]]; then
    warning "Docker is stopped. Starting it..."
    sudo systemctl start docker
  fi
}

#
# Install NPM
#
install_0_npm(){
  which npm > /dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    return 0
  fi
  notice "Installing NPM..."
  sudo apt-get update
  sudo apt-get install npm
}

install_diff_so_fancy(){
  which diff-so-fancy > /dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    notice "Installing diff-so-fancy for git..."
    sudo npm install -g diff-so-fancy
  fi

  PAGER=$(git config --get core.pager)
  if [[ ! -z ${PAGER} ]]; then
    return 0
  fi

  notice "Setting default pager to \"diff-so-fancy\""
  git config --global core.pager "diff-so-fancy | less --tabs=4 -RFX"
  git config --global color.diff-highlight.oldNormal "red bold"
  git config --global color.diff-highlight.oldHighlight "red bold 52"
  git config --global color.diff-highlight.newNormal "green bold"
  git config --global color.diff-highlight.newHighlight "green bold 22"
}

#
# Install docker & docker-compose
#
get_docker(){
  local LOOKUP_FILE="/etc/lsb-release"
  . ${LOOKUP_FILE}
  if [[ ! -f "/etc/apt/sources.list.d/docker.list" ]]; then
    notice "Installing GPG key for Docker repository..."
    sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
    echo "# ${DISTRIB_ID} ${DISTRIB_CODENAME} ${DISTRIB_RELEASE}
    deb https://apt.dockerproject.org/repo ubuntu-${DISTRIB_CODENAME} main
    " > /tmp/docker.list
    sudo cp /tmp/docker.list /etc/apt/sources.list.d/docker.list
    rm -f /tmp/docker.list
    notice "Updating repos..."
    sudo apt-get update
    notice "Installing latest Docker-engine version..."
    sudo apt-get install -y -qq docker-engine
    notice "Adding current user to docker group..."
    sudo usermod -aG docker ${USER}
    notice "Enabling startup Docker daemon..."
    sudo systemctl enable docker
    notice "Starting Docker daemon..."
    sudo service docker start
    notice "Installing Docker Compose..."
    curl -sL https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/run.sh -o /tmp/docker-compose
    sudo cp /tmp/docker-compose /usr/local/bin/ && chmod +x /usr/local/bin/docker-compose
    rm -f /tmp/docker-compose
  else
    check_docker
    docker images | grep 'docker/compose' | grep ${COMPOSE_VERSION} > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      COMPOSE_PREVIOUS_VERSION=$(docker images | grep 'docker/compose' | awk '{print $2}')
      notice "Updating Docker Compose..."
      if [[ ! -z ${COMPOSE_PREVIOUS_VERSION} ]]; then
        notice "Removing previous version..."
        docker rmi docker/compose:${COMPOSE_PREVIOUS_VERSION}
      fi
      curl -sL https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/run.sh -o /tmp/docker-compose
      notice "Copying new version to PATH"
      sudo cp /tmp/docker-compose /usr/local/bin/ && sudo chmod +x /usr/local/bin/docker-compose
      rm -f /tmp/docker-compose
    fi
  fi
}

#
# Download and set up Hub cli and alias it as git
#
get_hub(){
  local DEST="/usr/local/bin/"
  if [[ -f "${DEST}/hub" ]]; then
    return 0
  fi
  notice "Setting up GitHub CLI"
  local HUB_URL="https://github.com/github/hub/releases/download/v${HUB_VERSION}/hub-linux-amd64-${HUB_VERSION}.tgz"
  curl -sL ${HUB_URL} | tar xz
  if [[ -w ${DEST} ]]; then
    local PREFIX=""
  else
    warning "Path not writable by current user, please provide sudo password"
    local PREFIX="sudo"
  fi
  ${PREFIX} mv "hub-linux-amd64-${HUB_VERSION}/bin/hub" ${DEST}
  rm -rf hub-linux-amd64-*
}

#
# Function to add aliases to profile
#
create_alias(){
  local ALIAS_FILE="${HOME}/.bash_aliases"
  declare -i count=0
  declare -a KEYS=(ll git)
  declare -a VALUE=('ls -l' 'hub')
  for key in ${KEYS[*]}; do
    grep ${key} ${ALIAS_FILE} > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      alias ${key}="${VALUE[count]}"
    fi
    ((count++))
  done
  alias >> ${ALIAS_FILE}
}

#
# Install zsh and robbyrussell
#
install_zsh(){
  local ZSH_THEME="agnoster"
  which zsh > /dev/null 2>&1

  if [[ $? -eq 0 ]]; then
    return 0
  fi
  notice "Installing zsh shell..."
  sudo apt-get update
  sudo apt-get install zsh
  sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

  grep robbyrussell ${HOME}/.zshrc

  if [[ $? -eq 0 ]]; then
    sed -i 's/robbyrussell/agnoster/' ${HOME}/.zshrc
  fi
}

#
# Install patched fonts
#
install_fonts(){
  local FONTS=$(find ${HOME}/.local/share/fonts -name "*Powerline.ttf")

  if [[ ! -z ${FONTS} ]]; then
    return 0
  fi

  notice "Installing patched fonts..."
  git clone https://github.com/powerline/fonts.git
  ./fonts/install.sh
  rm -rf fonts
}

#
# Copy local configuration files for software
#
copy_local_configurations(){
  local DEST="${HOME}/.config"
  local SOURCE="$(pwd)/configs"
  local CONFIGS=$(ls ${SOURCE})

  for CONFIG in ${CONFIGS}; do
    cp -rf ${SOURCE}/${CONFIG} ${DEST}/${CONFIG}
  done
}

####### MAIN EXECUTION BLOCK #######

#
# Code that runs every function in the script except for helpers
#
main(){
  map_environment environment.yml
  supported_dists

  for function in ${1}; do
    ${function}
  done
}

EXCLUDES='log|notice|warning|fatal|map_environment|supported_dists|main|check_'
FUNCTIONS=$(typeset -F | egrep -v ${EXCLUDES} | awk '{print $3}')

main "${FUNCTIONS}"
