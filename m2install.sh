#!/usr/bin/env bash

# Magento 2 Bash Install Script
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# @copyright Copyright (c) 2015-2019 by Yaroslav Voronoy (y.voronoy@gmail.com)
# @license   http://www.gnu.org/licenses/

GLOBAL_ARGS="$@"
VERBOSE=1
CURRENT_DIR_NAME=$(basename "$(pwd)")
STEPS=

HTTP_HOST=http://mage2.dev/
BASE_PATH=${CURRENT_DIR_NAME}
DB_HOST=localhost
DB_USER=root
DB_PASSWORD=


ELASTICSEARCH_HOST=
ELASTICSEARCH_PORT=

MAGENTO_VERSION=2.2

DB_NAME=
USE_SAMPLE_DATA=
EE_PATH=magento2ee
INSTALL_EE=
INSTALL_B2B=
CONFIG_NAME=.m2install.conf
USE_WIZARD=1

GIT_CE_REPO="git@github.com:magento/magento2.git"
GIT_CE_SD_REPO="git@github.com:magento/magento2-sample-data.git"
GIT_EE_REPO=
GIT_EE_SD_REPO=
GIT_B2B_REPO=
GIT_CE_SD_PATH=magento2-sample-data
GIT_EE_SD_PATH=magento2-sample-data-ee
GIT_B2B_PATH=magento2b2b

SOURCE=
FORCE=
MAGE_MODE=dev

BIN_PHP=php
BIN_MAGE="-d memory_limit=2G bin/magento"
BIN_COMPOSER=$(command -v composer)
BIN_MYSQL="mysql"
BIN_GIT="git"

BACKEND_FRONTNAME="admin"
ADMIN_NAME="admin"
ADMIN_PASSWORD="123123q"
ADMIN_FIRSTNAME="Admin"
ADMIN_LASTNAME="Test"
ADMIN_EMAIL="admin@test.com"
TIMEZONE="America/Chicago"
LANGUAGE="en_US"
CURRENCY="USD"
REMOTE_DB=
REMOTE_DB_HOST=""
REMOTE_DB_PASSWORD=""
REMOTE_HOST=""
REMOTE_KEY=""
LOCAL_PORT=""

BUNDLED_EXTENSION=(
    amzn/amazon-pay-and-login-magento-2-module
    dotmailer/dotmailer-magento2-extension
    klarna/module-core
    klarna/module-kp
    klarna/module-ordermanagement
    temando/module-shipping-m2
    vertex/module-tax
)

function printVersion()
{
    printString "1.0.4"
}

function getScriptDirectory()
{
    echo "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )";
    return 0;
}
function getScriptDir()
{
  local source=
  local dir=
  local source="${BASH_SOURCE[0]}"
  while [ -h "$source" ]; do # resolve $SOURCE until the file is no longer a symlink
    local dir="$( cd -P "$( dirname "$source" )" && pwd )"
    source="$(readlink "$source")"
    [[ $source != /* ]] && source="$dir/$source" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  done
  dir="$( cd -P "$( dirname "$source" )" && pwd )"

  echo "$dir";
  return 0;
}

function checkDependencies()
{
    DEPENDENCIES=(
      php
      composer
      mysql
      mysqladmin
      git
      cat
      basename
      tar
      gunzip
      sed
      grep
      mkdir
      cp
      mv
      rm
      find
      chmod
      date
    )

    for util in "${DEPENDENCIES[@]}"
    do
        hash "${util}" &>/dev/null || printError "'${util}' is not found on this system" || exit 1
    done;

}

function askValue()
{
    MESSAGE="$1"
    READ_DEFAULT_VALUE="$2"
    READVALUE=
    if [ "${READ_DEFAULT_VALUE}" ]
    then
        MESSAGE="${MESSAGE} (default: ${READ_DEFAULT_VALUE})"
    fi
    MESSAGE="${MESSAGE}: "
    read -r -p "$MESSAGE" READVALUE
    if [[ $READVALUE = [Nn] ]]
    then
        READVALUE=''
        return
    fi
    if [ -z "${READVALUE}" ] && [ "${READ_DEFAULT_VALUE}" ]
    then
        READVALUE=${READ_DEFAULT_VALUE}
    fi
}

function askConfirmation() {
    if [ "$FORCE" ]
    then
        return 0;
    fi
    read -r -p "${1:-Are you sure? [y/N]} " response
    case $response in
        [yY][eE][sS]|[yY])
            retval=0
            ;;
        *)
            retval=1
            ;;
    esac
    return $retval
}

function printString()
{
    if [[ "$VERBOSE" -eq 1 ]]
    then
        echo "$@";
    fi
}

function printError()
{
    >&2 echo "ERROR: $@";
    return 1;
}

function printLine()
{
    if [[ "$VERBOSE" -eq 1 ]]
    then
        echo "--------------------------------------------------"
    fi
}

function setRequest()
{
    local _key=$1
    local _value=$2

    local expression="REQUEST_${_key}=${_value}"
    eval "${expression}";
}

function getRequest()
{
    local _key=$1
    local _variableName="REQUEST_${_key}";
    if [[ "${!_variableName:-}" ]]
    then
        echo "${!_variableName}"
        return 0;
    fi
    echo "";
    return 1;
}

function runCommand()
{
    local _prefixMessage=${1:-};
    local _suffixMessage=${2:-}
    if [[ "$VERBOSE" -eq 1 ]]
    then
        echo "${_prefixMessage}${CMD}${_suffixMessage}"
    fi

    # shellcheck disable=SC2086
    eval ${CMD};
}

function extract()
{
     if [ -f "$EXTRACT_FILENAME" ] ; then
         case $EXTRACT_FILENAME in
             *.tar.*|*.t*z*)
                CMD="tar $(getStripComponentsValue ${EXTRACT_FILENAME}) -xf ${EXTRACT_FILENAME}"
             ;;
             *.gz)              CMD="gunzip $EXTRACT_FILENAME" ;;
             *.zip)             CMD="unzip -qu -x $EXTRACT_FILENAME" ;;
             *)                 printError "'$EXTRACT_FILENAME' cannot be extracted"; exit 1; CMD='' ;;
         esac
        runCommand
     else
         printError "'$EXTRACT_FILENAME' is not a valid file"
     fi
}

function getStripComponentsValue()
{
    local stripComponents=
    local slashCount=
    slashCount=$(tar -tf "$1" | grep -v vendor | fgrep pub/index.php | sed 's/pub[/]index[.]php//' | sort | head -1 | tr -cd '/' | wc -m | tr -d ' ')

    if [[ "$slashCount" -gt 0 ]]
    then
        stripComponents="--strip-components=$slashCount"
    fi

    echo "$stripComponents";
}

function mysqlQuery()
{
    CMD="${BIN_MYSQL} -h${DB_HOST} -u${DB_USER} --password=\"${DB_PASSWORD}\" --execute=\"${SQLQUERY}\"";
    runCommand
}

function generateDBName()
{
    if [ -z "$DB_NAME" ]
    then
        prepareBasePath
        DB_NAME=${DB_USER}_${CURRENT_DIR_NAME}
    fi

    DB_NAME=$(sed -e "s/\//_/g; s/[^a-zA-Z0-9_]//g" <(${BIN_PHP} -r "print strtolower('$DB_NAME');"));
}

function prepareBasePath()
{
    BASE_PATH=$(echo "${BASE_PATH}" | sed "s/^\///g" | sed "s/\/$//g" );
}

function checkIfBasedOnDevelopBranch()
{
    if [ "$(ls -A ./)" ] && [ -d ".git" ]
    then
        ${BIN_GIT} rev-parse --abbrev-ref HEAD | grep '2.4-develop'
        if [ 0 = $? ]
        then
            return 0
        fi
    fi
    return 1
}

function prepareBaseURL()
{
    prepareBasePath
    HTTP_HOST=$(echo ${HTTP_HOST}/ | sed "s/\/\/$/\//g" );

    BASE_URL=${HTTP_HOST}${BASE_PATH}/
    if [ "$SOURCE" == 'git' ] && [ "${MAGENTO_VERSION}" == '2.4-develop' ] || checkIfBasedOnDevelopBranch
    then
        BASE_URL=${HTTP_HOST}${BASE_PATH}/pub/
    fi
    BASE_URL=$(echo "$BASE_URL" | sed "s/\/\/$/\//g" );
}

function initQuietMode()
{
    if [[ "$VERBOSE" -eq 1 ]]
    then
        return;
    fi

    BIN_MAGE="${BIN_PHP} ${BIN_MAGE} --quiet"
    BIN_COMPOSER="${BIN_PHP} ${BIN_COMPOSER} --quiet"
    BIN_GIT="${BIN_GIT} --quiet"

    FORCE=1
}

function getCodeDumpFilename()
{
    local codeDumpFilename="";
    if [[ -f "$(getRequest codedump)" ]]
    then
        codeDumpFilename="$(getRequest codedump)";
        echo "$codeDumpFilename";
        return 0;
    fi
    codeDumpFilename=$(find . -maxdepth 1 -name '*.tbz2' -o -name '*.tar.bz2' | head -n1)
    if [ "${codeDumpFilename}" == "" ]
    then
        codeDumpFilename=$(find . -maxdepth 1 -name '*.tar.gz' | grep -v 'logs.tar.gz' | head -n1)
    fi
    if [ ! "$codeDumpFilename" ]
    then
        codeDumpFilename=$(find . -maxdepth 1 -name '*.tgz' | head -n1)
    fi
    if [ ! "$codeDumpFilename" ]
    then
        codeDumpFilename=$(find . -maxdepth 1 -name '*.zip' | head -n1)
    fi

    echo "$codeDumpFilename";
    return 0;
}

function getDbDumpFilename()
{
    local dbDumpFilename="";
    if [[ -f "$(getRequest dbdump)" ]]
    then
        dbDumpFilename="$(getRequest dbdump)";
        echo "$dbDumpFilename";
        return 0;
    fi
    dbdumpFilename=$(find . -maxdepth 1 -name '*.sql.gz' | head -n1)
    if [ ! "$dbdumpFilename" ]
    then
        dbdumpFilename=$(find . -maxdepth 1 -name '*_db.gz' | head -n1)
    fi
    if [ ! "$dbdumpFilename" ]
    then
        dbdumpFilename=$(find . -maxdepth 1 -name '*.sql' | head -n1)
    fi
    echo "$dbdumpFilename";
    return 0;
}

function foundSupportBackupFiles()
{
    if [ -z getCodeDumpFilename ]
    then
        return 1;
    fi

    if [[ "$REMOTE_DB" ]]
    then
        return 0;
    fi

    if [ -z getDbDumpFilename ]
    then
        return 1;
    fi

    if [ ! -f "$(getCodeDumpFilename)" ] || [ ! -f "$(getDbDumpFilename)" ]
    then
        return 1;
    fi

    return 0;
}

function wizard()
{
    askValue "Enter Server Name of Document Root" "${HTTP_HOST}"
    HTTP_HOST=${READVALUE}
    askValue "Enter Base Path" "${BASE_PATH}"
    BASE_PATH=${READVALUE}
    askValue "Enter DB Host" "${DB_HOST}"
    DB_HOST=${READVALUE}
    askValue "Enter DB User" "${DB_USER}"
    DB_USER=${READVALUE}
    askValue "Enter DB Password" "${DB_PASSWORD}"
    DB_PASSWORD=${READVALUE}
    generateDBName
    askValue "Enter DB Name" "${DB_NAME}"
    DB_NAME=${READVALUE}

    if foundSupportBackupFiles
    then
        return;
    fi
    if askConfirmation "Do you want to install Sample Data (y/N)"
    then
        USE_SAMPLE_DATA=1
    fi
}

function noSourceWizard()
{
    if [[ "$SOURCE" ]]
    then
        return;
    fi
    if [[ ! "$SOURCE" ]] && askConfirmation "Do you want install Enterprise Edition (y/N)"
    then
        INSTALL_EE=1
    fi
    if [[ "$INSTALL_EE" ]] && askConfirmation "Do you want install B2B Extension (y/N)"
    then
         INSTALL_B2B=1
    fi
}

function printConfirmation()
{
    printComposerConfirmation
    printGitConfirmation
    prepareBaseURL
    printString "BASE URL: ${BASE_URL}"
    printString "BASE PATH: ${BASE_PATH}"
    printString "DB PARAM: ${DB_USER}@${DB_HOST}"
    printString "DB NAME: ${DB_NAME}"
    printString "DB PASSWORD: ${DB_PASSWORD}"
    printString "MAGE MODE: ${MAGE_MODE}"
    printString "BACKEND FRONTNAME: ${BACKEND_FRONTNAME}"
    printString "ADMIN NAME: ${ADMIN_NAME}"
    printString "ADMIN PASSWORD: ${ADMIN_PASSWORD}"
    printString "ADMIN FIRSTNAME: ${ADMIN_FIRSTNAME}"
    printString "ADMIN LASTNAME: ${ADMIN_LASTNAME}"
    printString "ADMIN EMAIL: ${ADMIN_EMAIL}"
    printString "TIMEZONE: ${TIMEZONE}"
    printString "LANGUAGE: ${LANGUAGE}"
    printString "CURRENCY: ${CURRENCY}"
    if [[ "$REMOTE_DB" ]]
    then
        printString "REMOTE DB HOST: ${REMOTE_DB_HOST}"
        printString "REMOTE HOST: ${REMOTE_HOST}"
        printString "REMOTE KEY: ${REMOTE_KEY}"
        printString "LOCAL PORT: ${LOCAL_PORT}"
        printString "REMOTE DB: ${REMOTE_DB}"
        printString "REMOTE DB PASSWORD: ${REMOTE_DB_PASSWORD}"
    fi
    if foundSupportBackupFiles
    then
        return;
    fi
    if [ "${USE_SAMPLE_DATA}" ]
    then
        printString "Sample Data will be installed."
    else
        printString "Sample Data will NOT be installed."
    fi
    if [ "${INSTALL_EE}" ]
    then
        printString "Magento EE will be installed."
    else
        printString "Magento EE will NOT be installed."
    fi
    if [ "${INSTALL_B2B}" ]
    then
        printString "Magento B2B will be installed."
    else
        printString "Magento B2B will NOT be installed."
    fi
    if [[ "$ELASTICSEARCH_HOST" ]]
    then  
        printString " "
        printString "========================= Checking Elasticsearch ========================="
        printString "ELASTICSEARCH HOST: ${ELASTICSEARCH_HOST}"
        printString "ELASTICSEARCH PORT: ${ELASTICSEARCH_PORT}"
        curl ${ELASTICSEARCH_HOST}:${ELASTICSEARCH_PORT} | grep 'You Know, for Search'
        tagline=$?
        if [ 0 = $tagline ]
            then
                printString "========================= Elasticsearch Found ========================="
            else
                printString " =========================> ELASTICSEARCH NOT FOUND!!! <========================= "
        fi
        printString " "
    fi
}

function showWizard()
{
    I=1;
    while [ "$I" -eq 1 ]
    do
        if [ "$USE_WIZARD" -eq 1 ]
        then
            showComposerWizzard
            showWizzardGit
            noSourceWizard
            wizard
        fi
        printLine
        printConfirmation
        if askConfirmation "Confirm That the Entered Data Is Correct? (y/N)"
        then
            I=0
        else
            USE_WIZARD=1
        fi
    done
}

function getConfigFiles()
{
    local configPaths[0]="$HOME/$CONFIG_NAME"
    configPaths[1]="$HOME/${CONFIG_NAME}.override"
    local recursiveconfigs=$( (find "$(pwd)" -maxdepth 1 -name "${CONFIG_NAME}" ;\
        x=$(pwd);\
        while [ "$x" != "/" ] ;\
        do x=$(dirname "$x");\
            find "$x" -maxdepth 1 -name "${CONFIG_NAME}";\
        done) | sed '1!G;h;$!d')
    configPaths=("${configPaths[@]}" "${recursiveconfigs[@]}" "./$(basename ${CONFIG_NAME})" "$(getScriptDir)/master.conf");
    echo "${configPaths[@]} "
    return 0;
}

function loadConfigFile()
{
    local filePath=
    local configPaths=("$@");
    for filePath in "${configPaths[@]}"
    do
        if [ -f "${filePath}" ]
        then
            source "$filePath"
            USE_WIZARD=0
        fi
    done
    generateDBName
}

function promptSaveConfig()
{
    if [ "$FORCE" ]
    then
        return;
    fi
    _local=$(dirname "$BASE_PATH")
    if [ "$_local" == "." ]
    then
        _local=
    else
        _local=$_local/
    fi
    if [ "$_local" != '/' ]
    then
        _local=${_local}\$CURRENT_DIR_NAME
    fi

    _configContent=$(cat << EOF
HTTP_HOST=$HTTP_HOST
BASE_PATH=$_local
DB_HOST=$DB_HOST
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
MAGENTO_VERSION=$MAGENTO_VERSION
INSTALL_EE=$INSTALL_EE
INSTALL_B2B=$INSTALL_B2B
GIT_CE_REPO=$GIT_CE_REPO
GIT_EE_REPO=$GIT_EE_REPO
MAGE_MODE=$MAGE_MODE
BACKEND_FRONTNAME=$BACKEND_FRONTNAME
ADMIN_NAME=$ADMIN_NAME
ADMIN_PASSWORD=$ADMIN_PASSWORD
ADMIN_FIRSTNAME=$ADMIN_FIRSTNAME
ADMIN_LASTNAME=$ADMIN_LASTNAME
ADMIN_EMAIL=$ADMIN_EMAIL
TIMEZONE=$TIMEZONE
LANGUAGE=$LANGUAGE
CURRENCY=$CURRENCY
REMOTE_DB_HOST=$REMOTE_DB_HOST
REMOTE_HOST=$REMOTE_HOST
REMOTE_KEY=$REMOTE_KEY
LOCAL_PORT=$LOCAL_PORT
REMOTE_DB=$REMOTE_DB
REMOTE_DB_PASSWORD=$REMOTE_DB_PASSWORD
ELASTICSEARCH_HOST=$ELASTICSEARCH_HOST
ELASTICSEARCH_PORT=$ELASTICSEARCH_PORT
EOF
)

    if [ "$(getConfigFiles)" ]
    then
        _currentConfigContent=$(cat "$HOME/$CONFIG_NAME")

        if [ "$_configContent" == "$_currentConfigContent" ]
        then
            return;
        fi

    fi

    configSavePath="$HOME/$CONFIG_NAME"
    if [ -f "${configSavePath}" ]
    then
        configSavePath="./$CONFIG_NAME"
    fi
    if askConfirmation "Do you want save config to ${configSavePath} (y/N)"
    then
        cat << EOF > ${configSavePath}
$_configContent
EOF
            printString "Config file has been created in ${configSavePath}";
        fi
    _local=
    configSavePath=
}

function dropDB()
{
    SQLQUERY="DROP DATABASE IF EXISTS ${DB_NAME}";
    mysqlQuery
}

function createNewDB()
{
    SQLQUERY="CREATE DATABASE IF NOT EXISTS ${DB_NAME}";
    mysqlQuery
}

function restore_db()
{
    dropDB
    createNewDB

    CMD="gunzip -cf \"$(getDbDumpFilename)\""
    if which pv > /dev/null
    then
        CMD="pv \"$(getDbDumpFilename)\" | gunzip -cf";
    fi

    # Don't be confused by double gunzip in following command. Some poorly
    # configured web servers can gzip everything including gzip files
    CMD="${CMD} | gunzip -cf | sed -e 's/DEFINER[ ]*=[ ]*[^*]*\*/\*/'
        | sed -e 's/TRIGGER[ ][\`][A-Za-z0-9_]*[\`][.]/TRIGGER /'
        | sed -e 's/AFTER[ ]\(INSERT\)\{0,1\}\(UPDATE\)\{0,1\}\(DELETE\)\{0,1\}[ ]ON[ ][\`][A-Za-z0-9_]*[\`][.]/AFTER \1\2\3 ON /'
        | grep -v 'mysqldump: Couldn.t find table' | grep -v 'Warning: Using a password'
        | ${BIN_MYSQL} -h${DB_HOST} -u${DB_USER} --password=\"${DB_PASSWORD}\" --force $DB_NAME";
    runCommand
}

function restore_code()
{
    EXTRACT_FILENAME="$(getCodeDumpFilename)"
    extract

    CMD="mkdir -p var pub/media pub/static"
    runCommand
}

function configure_files()
{
    CMD="find -L ./pub -type l -delete"
    runCommand
    updateMagentoEnvFile
    overwriteOriginalFiles
    #CMD="find . -type d -exec chmod 775 {} \; && find . -type f -exec chmod 664 {} \;"
    CMD="chmod -R 775 ."
    runCommand
    CMD="${BIN_PHP} ${BIN_COMPOSER} dump-autoload"
    runCommand

    patchDumps
}

function add_remote()
{
    updateEnvFileRemote
    patchRemote
}

function getRemoteDBUser()
{
    local user=(${REMOTE_DB//_/ })
    echo ${user[0]} ;
}

function updateEnvFileRemote()
{
    local deployConfigurator=$(cat << EOF
<?php

\$dbName = '${REMOTE_DB}';
\$dbUser = '$(getRemoteDBUser)';
\$dbPassword = '${REMOTE_DB_PASSWORD}';
\$localPort = '${LOCAL_PORT}';

EOF
);
    deployConfigurator+=$(cat << 'EOF'

function updateDbConnection($envConfig, $connectionDetails)
{
    unset($envConfig['db']['slave_connection']);

    foreach ($envConfig['db'] as $key => $connections) {
        if ($key != 'connection') {
            continue;
        }
        foreach ($connections as $connectionName => $connectionParams) {
            $envConfig['db'][$key][$connectionName] = $connectionDetails;
        }
    }

    return $envConfig;
}

$envConfig = require 'app/etc/env.php';
$envConfig = updateDbConnection($envConfig, array(
    'host' => "127.0.0.1:$localPort",
    'dbname' => $dbName,
    'username' => $dbUser,
    'password' => "$dbPassword",
    'model' => 'mysql4',
    'engine' => 'innodb',
    'initStatements' => 'SET NAMES utf8;',
    'active' => '1'
));

echo "<?php\nreturn " . var_export($envConfig, true) . "\n;";
EOF
);

 echo "$deployConfigurator" | ${BIN_PHP} > app/etc/env.php.generated
 mv app/etc/env.php.generated app/etc/env.php
}

function addToBootstrap()
{
    echo "$1" >> app/bootstrap.php;
}

function patchRemote()
{
  local sshKey=''
  if [[ "$REMOTE_KEY" ]]
  then
    sshKey="-i ${REMOTE_KEY} "
  fi
  addToBootstrap "//patched by m2install."

  local ssh_command="ssh ${sshKey}-o ConnectTimeout=10 -o StrictHostKeyChecking=no -4fN -L ${LOCAL_PORT}:${REMOTE_DB_HOST} ${REMOTE_HOST}"

  if ! pgrep -f -x "${ssh_command}" > /dev/null
  then
    echo "Start tunnel"
     eval $ssh_command >> /dev/null
  fi
  SQLQUERY="SELECT code FROM ${REMOTE_DB}.$(getTablePrefix)store WHERE code != 'admin';";

  local stores=$(mysql -h127.0.0.1 -N -u$(getRemoteDBUser) -P${LOCAL_PORT} --execute="${SQLQUERY}")
  echo "$stores" | while IFS= read -r line ;
  do
    addToBootstrap "\$_ENV['CONFIG__STORES__${line}__WEB__SECURE__BASE_URL'] = '${BASE_URL}';"
    addToBootstrap "\$_ENV['CONFIG__STORES__${line}__WEB__UNSECURE__BASE_URL'] = '${BASE_URL}';"
  done
  addToBootstrap "\$_ENV['CONFIG__DEFAULT__WEB__UNSECURE__BASE_URL'] = '${BASE_URL}';"
  addToBootstrap "\$_ENV['CONFIG__DEFAULT__WEB__SECURE__BASE_URL'] = '${BASE_URL}';"

  addToBootstrap "\$command = '$ssh_command';"
  addToBootstrap 'exec("ps aux | grep -v \" grep\" | grep \"$command\" | tr -s \" \" | cut -d \" \" -f 2", $pids);'
  addToBootstrap 'if (count($pids) === 0) {'
  addToBootstrap '    exec($command . " >> /dev/null", $output, $exitCode);';
  addToBootstrap '    if ($exitCode > 0) {'
  addToBootstrap '        throw new \Exception("Remote Host ${REMOTE_HOST} is unavailable, check your network settings or VPN connection");'
  addToBootstrap '    }'
  addToBootstrap '    exec("ps aux | grep -v \" grep\" | grep \"$command\" | tr -s \" \" | cut -d \" \" -f 2", $pids);'
  addToBootstrap '}'
  addToBootstrap 'file_put_contents("kill_tunnel.sh", PHP_EOL . "kill " . implode(" ", $pids));'
  addToBootstrap ""
}

function patchDumps()
{
  patch -p1 <<'EOF'
diff --git a/vendor/magento/module-backend/Block/Dashboard/Orders/Grid.php b/vendor/magento/module-backend/Block/Dashboard/Orders/Grid.php
index 5027978..9df3c24 100644
--- a/vendor/magento/module-backend/Block/Dashboard/Orders/Grid.php
+++ b/vendor/magento/module-backend/Block/Dashboard/Orders/Grid.php
@@ -92,6 +92,11 @@ class Grid extends \Magento\Backend\Block\Dashboard\Grid
     protected function _afterLoadCollection()
     {
         foreach ($this->getCollection() as $item) {
+            // patched by m2install.
+            // To revert patch remove next lines from 95 to 99
+            if (is_null($item->getBillingAddress())) {
+                return $this;
+            }
             $item->getCustomer() ?: $item->setCustomer($item->getBillingAddress()->getName());
         }
         return $this;
EOF
}

function appConfigImport()
{
    if ${BIN_PHP} bin/magento | grep -q app:config:import
    then
        CMD="${BIN_PHP} bin/magento app:config:import -n"
        runCommand
    fi
}

function validateDeploymentFromDumps()
{
    local files=(
      'composer.json'
      'composer.lock'
      'index.php'
      'pub/index.php'
      'pub/static.php'
    );
    local directories=("app" "bin" "dev" "lib" "pub/errors" "setup" "vendor");
    missingDirectories=();
    for dir in "${directories[@]}"
    do
        if [ ! -d "$dir" ]; then
            missingDirectories+=("$dir");
        fi
    done
    if [[ "${missingDirectories[@]-}" ]]
    then
        echo "The following directories are missing: ${missingDirectories[@]}";
    fi

    missingFiles=()
    for file in "${files[@]}"
    do
        if [ ! -f "$file" ]; then
            missingFiles+=("$file");
        fi
    done
    if [[ "${missingFiles[@]-}" ]]
    then
        echo "The following files are missing: ${missingFiles[@]}";
    fi
    if [[ "${missingDirectories[@]-}" || "${missingFiles[@]-}" ]]
    then
        printError "Download missing files and directories from vanilla magento"
    fi
}

function switchSearchEngineToDefaultEngine()
{
  local red=`tput setaf 1`
  local green=`tput setaf 2`
  local yellow=`tput setaf 3`
  local default=`tput sgr0`
  local engine=$(getConfig 'catalog/search/engine' "value");
  [ "$engine" == 'mysql' ] \
    || [ -z "$engine" ] \
    && [ ! -z "$(grep -s engine app/etc/config.php | grep elastic)" ] \
    && [ ! -z "$(grep -s engine app/etc/env.php.merchant | grep elastic)" ] \
    && [ ! -z "$(grep -s engine app/etc/config.local.php.merchant | grep elastic)" ] \
    && return 0;

  [ -z "$engine" ] || [ "$engine" == 'mysql' ] && engine=elasticsearch;

  deleteConfig 'catalog/search/engine'
  local stepsToTake=" - Run php bin/magento indexer:reindex catalogsearch_fulltext"
  [[ ! -z `grep engine app/etc/config.php | grep elastic` ]] \
        && stepsToTake=" - Edit app/etc/config.php file and remove section engine => elasticsearch
${stepsToTake}"
  cat <<endmessage
${yellow}
####################################################################################
Warning: A Search Engine has been switched from ${engine} to ${green}mysql${yellow}
If you need to see products on frontend follow the steps below:
${stepsToTake}
####################################################################################
${default}
endmessage
}

function configure_db()
{
  setConfig 'web/secure/base_url' "${BASE_URL}";
  setConfig 'web/unsecure/base_url' "${BASE_URL}";
  setConfig 'google/analytics/active' '0';
  setConfig 'google/adwords/active' '0';
  setConfig 'msp_securitysuite_twofactorauth/general/enabled' '0';
  setConfig 'msp_securitysuite_recaptcha/backend/enabled' '0';
  setConfig 'msp_securitysuite_recaptcha/frontend/enabled' '0';
  setConfig 'admin/security/session_lifetime' '31536000';
  setConfig 'admin/startup/menu_item_id' 'Magento_Backend::system_store';
  deleteConfig 'web/unsecure/base_link_url';
  deleteConfig 'web/secure/base_link_url';
  deleteConfig 'web/unsecure/base_static_url';
  deleteConfig 'web/unsecure/base_media_url';
  deleteConfig 'web/secure/base_static_url';
  deleteConfig 'web/secure/base_media_url';
  deleteConfig "web/cookie/cookie_domain";
  deleteConfig "web/secure/use_in_adminhtml";
  deleteConfig "web/secure/use_in_frontend";
  deleteConfig "admin/url/custom";
  deleteConfig "admin/url/custom_path";
  deleteConfig "admin/url/use_custom";
  deleteConfig "admin/url/use_custom_path";
  deleteConfig 'system/full_page_cache/fastly/fastly_api_key';
  deleteConfig 'system/full_page_cache/caching_application';
  deleteConfig 'catalog/placeholder/%' 'LIKE';
  deleteConfig 'algoliasearch_credentials/credentials/application_id';
  deleteConfig 'algoliasearch_credentials/credentials/search_only_api_key';
  deleteConfig 'algoliasearch_credentials/credentials/api_key';
  deleteConfig 'algoliasearch_credentials/credentials/enable_backend';
  deleteConfig 'algoliasearch_credentials/credentials/enable_frontend';
  deleteConfig 'services_connector/services_connector_integration/production_api_key';
  deleteConfig 'services_connector/services_connector_integration/sandbox_api_key';
  deleteConfig 'services_connector/services_id/project_name';
  deleteConfig 'services_connector/services_id/environment_name';
  deleteConfig 'services_connector/services_id/environment';
  deleteConfig 'services_connector/services_id/project_id';
  deleteConfig 'services_connector/services_id/environment_id';

  resetAdminPassword
  switchSearchEngineToDefaultEngine
}

function setConfig()
{
  local path="${1}";
  local value="${2}";

  SQLQUERY="UPDATE ${DB_NAME}.$(getTablePrefix)core_config_data SET ${DB_NAME}.$(getTablePrefix)core_config_data.value = '${value}' WHERE path = '${path}'"
  mysqlQuery
}

function getConfig()
{
  local output=
  local path="${1}";
  local field="${2}";

  SQLQUERY="SELECT ${field} FROM ${DB_NAME}.$(getTablePrefix)core_config_data WHERE path = '${path}'";
  output=$(mysqlQuery)
  echo "$output" | grep -v "$field"
}

function deleteConfig()
{
  local path="${1}";
  local where="=";
  if [ ! -z $2 ]
  then
    where="${2}";
  fi

  SQLQUERY="DELETE FROM ${DB_NAME}.$(getTablePrefix)core_config_data WHERE path ${where} '${path}'";
  mysqlQuery
}

function resetAdminPassword()
{
    SQLQUERY="UPDATE ${DB_NAME}.$(getTablePrefix)admin_user SET ${DB_NAME}.$(getTablePrefix)admin_user.email = '${ADMIN_EMAIL}' WHERE ${DB_NAME}.$(getTablePrefix)admin_user.username = '${ADMIN_NAME}'"
    mysqlQuery
    CMD="${BIN_PHP} ${BIN_MAGE} admin:user:create
        --admin-user='${ADMIN_NAME}'
        --admin-password='${ADMIN_PASSWORD}'
        --admin-email='${ADMIN_EMAIL}'
        --admin-firstname='${ADMIN_FIRSTNAME}'
        --admin-lastname='${ADMIN_LASTNAME}'"
    runCommand
}

function overwriteOriginalFiles()
{
    if [ -f app/etc/config.local.php ]
    then
        CMD="mv app/etc/config.local.php app/etc/config.local.php.merchant"
        runCommand
    fi

    if [ ! -f pub/static.php ]
    then
        CMD="curl -s -o pub/static.php https://raw.githubusercontent.com/magento/magento2/${MAGENTO_VERSION}/pub/static.php"
        runCommand
    fi

    if [ -f .htaccess ] && [ ! -f .htaccess.merchant ]
    then
        CMD="mv .htaccess .htaccess.merchant"
        runCommand
    fi
    CMD="curl -s -o .htaccess https://raw.githubusercontent.com/magento/magento2/${MAGENTO_VERSION}/.htaccess"
    runCommand

    if [ -f pub/.htaccess ] && [ ! -f pub/.htaccess.merchant ]
    then
        CMD="mv pub/.htaccess pub/.htaccess.merchant"
        runCommand
    fi
    CMD="curl -s -o pub/.htaccess https://raw.githubusercontent.com/magento/magento2/${MAGENTO_VERSION}/pub/.htaccess"
    runCommand

    if [ -f pub/static/.htaccess ] && [ ! -f pub/static/.htaccess.merchant ]
    then
        CMD="mv pub/static/.htaccess pub/static/.htaccess.merchant"
        runCommand
    fi
    CMD="curl -s -o pub/static/.htaccess https://raw.githubusercontent.com/magento/magento2/${MAGENTO_VERSION}/pub/static/.htaccess"
    runCommand

    if [ -f pub/media/.htaccess ] && [ ! -f pub/media/.htaccess.merchant ]
    then
        CMD="mv pub/media/.htaccess pub/media/.htaccess.merchant"
        runCommand
    fi
    CMD="curl -s -o pub/media/.htaccess https://raw.githubusercontent.com/magento/magento2/${MAGENTO_VERSION}/pub/media/.htaccess"
    runCommand
}
function getTablePrefix()
{
    echo $(grep 'table_prefix' app/etc/env.php | head -n1 | sed "s/[a-z'_ ]*[=][>][ ]*[']//" | sed "s/['][,]*//")
    return 0;
}

function updateMagentoEnvFile()
{
    if [ -f app/etc/env.php ] && [ ! -f app/etc/env.php.merchant ]
    then
        CMD="cp app/etc/env.php app/etc/env.php.merchant"
        runCommand
    fi
    if [ -f app/etc/env.support.backup ] && [ ! -f app/etc/env.php ]
    then
        CMD="cp app/etc/env.support.backup app/etc/env.php"
        runCommand
    fi
    if [ ! -f app/etc/env.php ]
    then
        CMD="echo -e \"<?php\nreturn array('install'=>array('date'=>'$(date)'),'db'=>array('connection'=>array('default'=>array())));\n\" > app/etc/env.php"
        runCommand
    fi
    local deployConfigurator=$(cat << EOF
<?php

\$dbHost = '${DB_HOST}';
\$dbName = '${DB_NAME}';
\$dbUser = '${DB_USER}';
\$dbPassword = '${DB_PASSWORD}';
\$frontName = '${BACKEND_FRONTNAME}';

EOF
);
    deployConfigurator+=$(cat << 'EOF'

function updateMode($envConfig, $mode)
{
    $envConfig['MAGE_MODE'] = $mode;
    return $envConfig;
}

function updateBackendFrontName($envConfig, $frontName)
{
    $envConfig['backend'] = array('frontName' => $frontName);
    return $envConfig;
}

function updateDbConnection($envConfig, $connectionDetails)
{
    unset($envConfig['db']['slave_connection']);

    foreach ($envConfig['db'] as $key => $connections) {
        if ($key != 'connection') {
            continue;
        }
        foreach ($connections as $connectionName => $connectionParams) {
            $envConfig['db'][$key][$connectionName] = $connectionDetails;
        }
    }

    return $envConfig;
}

function updateSessionConfiguration($envConfig, $value)
{
    $envConfig['session'] = array('save' => $value);
    return $envConfig;
}

function removeNonDefaultConfiguration($envConfig)
{
    $allowedConfigPaths = array(
        'backend',
        'crypt',
        'db',
        'resource',
        'x-frame-options',
        'MAGE_MODE',
        'session',
        'cache_types',
        'install'
    );
    foreach ($envConfig as $path => $value) {
      if (!in_array($path, $allowedConfigPaths)) {
          unset($envConfig[$path]);
      }
    }

    return $envConfig;
}
$envConfig = require 'app/etc/env.php';
$envConfig = removeNonDefaultConfiguration($envConfig);
$envConfig = updateSessionConfiguration($envConfig, 'files');
$envConfig = updateDbConnection($envConfig, array(
    'host' => "$dbHost",
    'dbname' => "$dbName",
    'username' => "$dbUser",
    'password' => "$dbPassword",
    'model' => 'mysql4',
    'engine' => 'innodb',
    'initStatements' => 'SET NAMES utf8;',
    'active' => '1'
));
$envConfig = updateBackendFrontName($envConfig, $frontName);
$envConfig = updateMode($envConfig, 'default');
echo "<?php\nreturn " . var_export($envConfig, true) . "\n;";
EOF
);

 echo "$deployConfigurator" | ${BIN_PHP} > app/etc/env.php.generated
 mv app/etc/env.php.generated app/etc/env.php
}

function deployStaticContent()
{
    if [[ "$MAGE_MODE" == "dev" ]]
    then
        return;
    fi

    CMD="${BIN_PHP} ${BIN_MAGE} setup:static-content:deploy"
    runCommand
}

function compileDi()
{
    if [[ "$MAGE_MODE" == "dev" ]]
    then
        return;
    fi
    CMD="${BIN_PHP} ${BIN_MAGE} setup:di:compile"
    runCommand
}

function installSampleData()
{
    if ${BIN_PHP} bin/magento --version | grep -q beta
    then
        _installSampleDataForBeta;
    elif [ "$SOURCE" == 'git' ]
    then
        _installGitSampleData;
    else
        _installSampleData;
    fi
}

function _installSampleData()
{
    if ! ${BIN_PHP} bin/magento | grep -q sampledata:deploy
    then
        printString "Your version does not support sample data"
        return;
    fi

    if [ -f "${HOME}/.config/composer/auth.json" ]
    then
        if [ -d "var/composer_home" ]
        then
            CMD="cp ${HOME}/.config/composer/auth.json var/composer_home/"
            runCommand
        fi
    fi

    if [ -f "${HOME}/.composer/auth.json" ]
    then
        if [ -d "var/composer_home" ]
        then
            CMD="cp ${HOME}/.composer/auth.json var/composer_home/"
            runCommand
        fi
    fi
    if ! grep -q 'https://repo.magento.com' composer.json;
    then
        CMD="${BIN_PHP} ${BIN_COMPOSER} config repositories.magento composer https://repo.magento.com"
	runCommand
    fi

    CMD="${BIN_PHP} ${BIN_MAGE} sampledata:deploy"
    runCommand
    CMD="${BIN_PHP} ${BIN_MAGE} setup:upgrade"
    runCommand

    if [ -f "var/composer_home/auth.json" ]
    then
        CMD="rm var/composer_home/auth.json"
        runCommand
    fi
}

function _installSampleDataForBeta()
{
    CMD="${BIN_PHP} ${BIN_COMPOSER} config repositories.magento composer http://packages.magento.com"
    runCommand
    CMD="${BIN_PHP} ${BIN_COMPOSER} require magento/sample-data:~1.0.0-beta"
    runCommand
    CMD="${BIN_PHP} ${BIN_MAGE} setup:upgrade"
    runCommand
    CMD="${BIN_PHP} ${BIN_MAGE} sampledata:install admin"
    runCommand
}

function _installGitSampleData()
{
    CMD="${BIN_GIT} clone --branch $MAGENTO_VERSION --single-branch $GIT_CE_SD_REPO $GIT_CE_SD_PATH"
    runCommand
    CMD="${BIN_PHP} -f $GIT_CE_SD_PATH/dev/tools/build-sample-data.php -- --ce-source=."
    runCommand

    if [[ "$GIT_EE_SD_REPO" ]] && [[ "$INSTALL_EE" ]]
    then
        CMD="${BIN_GIT} clone --branch $MAGENTO_VERSION --single-branch $GIT_EE_SD_REPO $GIT_EE_SD_PATH"
        runCommand
        CMD="${BIN_PHP} -f $GIT_EE_SD_PATH/dev/tools/build-sample-data.php -- --ce-source=. --ee-source=$MAGENTO_EE_PATH"
        runCommand
    fi

    CMD="${BIN_PHP} ${BIN_MAGE} setup:upgrade"
    runCommand
}

function installB2B()
{
    if [ -z "$B2B_VERSION" ]
    then
        getB2Bversion
    fi

    if [ "${SOURCE}" == 'git' ]
    then
        validateGitRepository "${GIT_B2B_REPO}" "${B2B_VERSION}"
        CMD="${BIN_GIT} clone --branch ${B2B_VERSION} --single-branch ${GIT_B2B_REPO} ${GIT_B2B_PATH}"
        runCommand
        CMD="${BIN_PHP} dev/tools/build-ee.php --ce-source $(pwd) --ee-source ${GIT_B2B_PATH}"
        runCommand
        CMD="rm -rf var/* generation/*"
        runCommand
    else
        CMD="${BIN_PHP} ${BIN_COMPOSER} require magento/extension-b2b"
        runCommand
    fi
    CMD="${BIN_PHP} ${BIN_MAGE} setup:upgrade"
    runCommand
}

function getB2Bversion()
{
    REAL_MAGENTO_VERSION=`${BIN_PHP} bin/magento --version`
    MAGENTO_MAJOR_VERSION=`echo "${REAL_MAGENTO_VERSION}" | sed 's/.*2\.\([0-9]*\)\.\([0-9]*\).*/\1/'`
    MAGENTO_MINOR_VERSION=`echo "${REAL_MAGENTO_VERSION}" | sed 's/.*2\.\([0-9]*\)\.\([0-9]*\).*/\2/'`
    if [ $MAGENTO_MAJOR_VERSION -ge 4 ] && [ $MAGENTO_MINOR_VERSION -ge 1 ]
    then
        B2B_VERSION_MAJOR=$(( `echo "${MAGENTO_MAJOR_VERSION}"` -1 ))
        B2B_VERSION_MINOR=$(( `echo "${MAGENTO_MINOR_VERSION}"` -1 ))
    else
        B2B_VERSION_MAJOR=$(( `echo "${MAGENTO_MAJOR_VERSION}"` -2 ))
        B2B_VERSION_MINOR=$MAGENTO_MINOR_VERSION
    fi
    B2B_VERSION="1.${B2B_VERSION_MAJOR}.${B2B_VERSION_MINOR}"
}

function linkEnterpriseEdition()
{
    if [ "${SOURCE}" == 'composer' ]
    then
        return;
    fi
    if [ "${EE_PATH}" ] && [ "$INSTALL_EE" ]
    then
        if [ ! -d "$EE_PATH" ]
        then
            printError "There is no Enterprise Edition directory ${EE_PATH}"
            printString "Use absolute or relative path to EE code base or [N] to skip it"
            exit 1
        fi
        CMD="${BIN_PHP} ${EE_PATH}/dev/tools/build-ee.php --ce-source $(pwd) --ee-source ${EE_PATH}"
        runCommand
        CMD="cp ${EE_PATH}/composer.json $(pwd)/"
        runCommand
        CMD="cp ${EE_PATH}/composer.lock $(pwd)/"
        runCommand
    fi
}

function runComposerInstall()
{
    CMD="${BIN_PHP} ${BIN_COMPOSER} install"
    runCommand
}

function installMagento()
{
    if [ "${SOURCE}" == 'git' ]
    then
        CMD="${BIN_PHP} ${BIN_COMPOSER} config repositories.magento composer https://repo.magento.com/"
        runCommand
        # Install Bundled Extensions for version 2.2.+
        if [[ $MAGENTO_VERSION =~ ^2\.[^01]\..* ]]
        then
            for be in "${BUNDLED_EXTENSION[@]}" 
            do
                CMD="composer require --quiet ${be}"
                runCommand
            done
        fi
    fi

    CMD="rm -rf var/generation/*"
    runCommand

    CMD="${BIN_PHP} ${BIN_MAGE} --no-interaction setup:uninstall"
    runCommand

    dropDB
    createNewDB

    CMD="${BIN_PHP} ${BIN_MAGE} setup:install \
    --base-url=${BASE_URL} \
    --db-host=${DB_HOST} \
    --db-name=${DB_NAME} \
    --db-user=${DB_USER} \
    --admin-firstname=${ADMIN_FIRSTNAME} \
    --admin-lastname=${ADMIN_LASTNAME} \
    --admin-email=${ADMIN_EMAIL} \
    --admin-user=${ADMIN_NAME} \
    --admin-password=${ADMIN_PASSWORD} \
    --language=${LANGUAGE} \
    --currency=${CURRENCY} \
    --timezone=${TIMEZONE} \
    --use-rewrites=1 \
    --backend-frontname=${BACKEND_FRONTNAME}"
    if [ "${DB_PASSWORD}" ]; then
        CMD="${CMD} --db-password=${DB_PASSWORD}"
    fi
    if [ "${ELASTICSEARCH_HOST}" ]; then
        CMD="${CMD} --elasticsearch-host=${ELASTICSEARCH_HOST} --elasticsearch-port=${ELASTICSEARCH_PORT}"
    fi
    runCommand
}

function downloadSourceCode()
{
    if [ "$(ls -A ./)" ]; then
        printError "Can't download source code from ${SOURCE} since current directory doesn't empty."
        printString "You can remove all files from current directory using next command:"
        printString "ls -A | xargs rm -rf"
        exit 1;
    fi
    if [ "$SOURCE" == 'composer' ]
    then
        composerInstall
    fi

    if [ "$SOURCE" == 'git' ]
    then
        gitClone
    fi

    if [ "$SOURCE" == 'worktree' ]
    then
        gitWorktree
    fi
}

function composerInstall()
{
    if [ "$INSTALL_EE" ]
    then
        CMD="${BIN_PHP} ${BIN_COMPOSER} create-project --repository-url=https://repo.magento.com/ magento/project-enterprise-edition . ${MAGENTO_VERSION}"
        runCommand
    else
        CMD="${BIN_PHP} ${BIN_COMPOSER} create-project --repository-url=https://repo.magento.com/ magento/project-community-edition . ${MAGENTO_VERSION}"
        runCommand
    fi
}

showComposerWizzard()
{
    if [ "$SOURCE" != 'composer' ]
    then
        return;
    fi
    askValue "Composer Magento version" "${MAGENTO_VERSION}"
    MAGENTO_VERSION=${READVALUE}
    if askConfirmation "Do you want to install Enterprise Edition (y/N)"
    then
        INSTALL_EE=1
    fi
    if [[ "$INSTALL_EE" ]] && askConfirmation "Do you want install B2B Extension (y/N)"
    then
        INSTALL_B2B=1
    fi

}

printComposerConfirmation()
{
    if [ "$SOURCE" != 'composer' ]
    then
        return;
    fi
    printString "Magento code will be downloaded from composer";
    printString "Composer version: $MAGENTO_VERSION";
}

function showWizzardGit()
{
    if [ "$SOURCE" != 'git' ]
    then
        return
    fi
    askValue "Git CE repository" ${GIT_CE_REPO}
    GIT_CE_REPO=${READVALUE}
    askValue "Git EE repository" ${GIT_EE_REPO}
    GIT_EE_REPO=${READVALUE}
    askValue "Git branch" ${MAGENTO_VERSION}
    MAGENTO_VERSION=${READVALUE}
    if askConfirmation "Do you want to install Enterprise Edition (y/N)"
    then
        INSTALL_EE=1
    fi
    if [[ "$INSTALL_EE" ]] && askConfirmation "Do you want install B2B Extension (y/N)"
    then
        INSTALL_B2B=1
    fi
}

function gitClone()
{
    validateGitRepository "${GIT_CE_REPO}" "${MAGENTO_VERSION}"
    validateGitRepository "${GIT_EE_REPO}" "${MAGENTO_VERSION}"

    CMD="${BIN_GIT} clone --branch $MAGENTO_VERSION --single-branch $GIT_CE_REPO ."
    runCommand

    if [[ "$GIT_EE_REPO" ]] && [[ "$INSTALL_EE" ]]
    then
        CMD="${BIN_GIT} clone --branch $MAGENTO_VERSION --single-branch $GIT_EE_REPO $EE_PATH"
        runCommand
    fi
}

function gitWorktree()
{
  local currentDir=$(pwd);
  local worktreeCEPath="$(getWorktreePath CE)"

  validateGitRepository "${worktreeCEPath}" "$MAGENTO_VERSION"
  cd "$worktreeCEPath"
  CMD="git worktree add $currentDir $MAGENTO_VERSION"
  runCommand

  if [[ "$INSTALL_EE" ]]
  then
    cd "$currentDir"
    local worktreeEEPath="$(getWorktreePath EE)"
    validateGitRepository "${worktreeEEPath}" "$MAGENTO_VERSION"
    cd "$worktreeEEPath"
    CMD="git worktree add ${currentDir}/${EE_PATH} $MAGENTO_VERSION"
    runCommand
  fi
  cd "$currentDir"
}

function getWorktreePath()
{
  local ee=${1:-CE}
  local configName="CONFIG_GIT_WORKTREE_${ee}_PATH"
  local defaultValue="../repo"
  [ "$ee" == "EE" ] && defaultValue="../repo/magento2ee"

  if [ -z ${!configName} ]
  then
    eval "read -p \"Git Worktree requires path to local GIT ${ee} repository (Default: ${defaultValue}): \" ${configName}"
  fi
  echo "${!configName:-${defaultValue}}";
}

function validateGitRepository()
{
    local repoName=$1
    local versionName=$2

    local isBranchExists=$(${BIN_GIT} ls-remote ${repoName} | grep -F ${versionName})
    if [ ! "$isBranchExists" ]
    then
        printError "Requested tag or branch ${versionName} does not exists in ${repoName}"
        exit 1;
    fi
}

function printGitConfirmation()
{
    if [ "$SOURCE" != 'git' ]
    then
        return
    fi
    printString "Magento code will be downloaded from GIT";
    printString "Git CE repository: ${GIT_CE_REPO}"
    printString "Git EE repository: ${GIT_EE_REPO}"
    printString "Git branch: ${MAGENTO_VERSION}"
    if [[ ! -z $INSTALL_B2B ]]
    then
        printString "Git B2B repository: ${GIT_B2B_REPO}"
        printString "Git B2B branch: ${B2B_VERSION}"
    fi
}

function checkArgumentHasValue()
{
    if [ ! "$2" ]
    then
        printError "$1 Argument is empty."
        printLine
        printUsage
        exit
    fi
}

function isInputNegative()
{
    if [[ $1 = [Nn][oO] ]] || [[ $1 = [Nn] ]] || [[ $1 = [0] ]]
    then
        return 0;
    else
        return 1;
    fi
}

function validateStep()
{
    local _step=$1;
    local _steps="restore_db restore_code configure_db configure_files configure installB2B add_remote"
    if echo "$_steps" | grep -q "$_step"
    then
        if type -t "$_step" &>/dev/null
        then
            return 0;
        fi
    fi
    return 1;
}

function prepareSteps()
{
    local _step;
    local _steps;

    _steps=(${STEPS[@]//,/ })
    STEPS=
    for _step in "${_steps[@]}"
    do
        if validateStep "$_step"
        then
          addStep "$_step"
        fi
    done
}

function addStep()
{
  local _step=$1
  STEPS+=($_step)
}

function setProductionMode()
{
    CMD="${BIN_PHP} ${BIN_MAGE} deploy:mode:set production"
    runCommand
}

function setFilesystemPermission()
{
    CMD="chmod u+x ./bin/magento"
    runCommand
    local _writeableDirectories="./var ./pub/media ./pub/static ./app/etc"
    if [ -d './generated' ]
    then
        _writeableDirectories="$_writeableDirectories ./generated"
    fi
    CMD="chmod -R 2777 ${_writeableDirectories}"
    runCommand
}

function executePostDeployScript()
{
    if [ ! "$(getRequest skipPostDeploy)" ] && [ -f "$1" ]
    then
        printString "==> Run the post deploy $1"
        source "$1";
        printString "==> Post deploy script has been finished"
    fi
    return 0;
}

function warmCache()
{
    echo "Cache warm up ${BASE_URL}. Response code: $(curl -s -l -I ${BASE_URL} | head -n 1 | awk '{print $2}')"
}

function afterInstall()
{
    if [[ "$MAGE_MODE" == "production" ]]
    then
        setProductionMode
    fi
    executePostDeployScript "$(getScriptDirectory)/post-deploy"
    executePostDeployScript "$HOME/post-deploy"
    setFilesystemPermission
    if [ -z "$REMOTE_DB" ]
    then
        addStep "appConfigImport"
    fi
    warmCache
}

function executeSteps()
{
    local _steps=("$@")
    for step in "${_steps[@]}"
    do
        if [ "${step}" ]
        then
            CMD="${step}"
            runCommand "=> "
        fi
    done
}

function printUsage()
{
    cat <<EOF
$(basename "$0") is designed to simplify the installation process of Magento 2
and deployment of client dumps created by Magento 2 Support Extension.

Usage: $(basename "$0") [options]
Options:
    -h, --help                           Get this help.
    -s, --source (git, composer)         Get source code.
    -f, --force                          Install/Restore without any confirmations.
    --sample-data (yes, no)              Install sample data.
    --ee                                 Install Enterprise Edition.
    --b2b                                Install B2B Extension.
    -v, --version                        Magento Version - it means: Composer version or GIT Branch
    --mode (dev, prod)                   Magento Mode. Dev mode does not generate static & di content.
    --quiet                              Quiet mode. Suppress output all commands
    --skip-post-deploy                   Skip the post deploy script if it is exist
    --step (restore_code,restore_db      Specify step through comma without spaces.
        configure_db,configure_files     - Example: $(basename "$0") --step restore_db,configure_db
        installB2B --b2b)                - Example: $(basename "$0") --step installB2B --b2b
    --restore-table                      Restore only the specific table from DB dumps
    --debug                              Enable debug mode
    --php                                Specify path to PHP CLI (php71 or /usr/bin/php71)
    --remote-db                          Remote database name
    --es-host, --elasticsearch-host      Set the Elasticsearch host
    --es-port, --elasticsearch-port      Set the Elasticsearch port
    --uninstall                          Delete database and application from the current folder
    _________________________________________________________________________________________________
    --ee-path (/path/to/ee)              (DEPRECATED use --ee flag) Path to Enterprise Edition.
EOF
}

function uninstallAction()
{
  cleanupCurrentDirectory
  dropDB
}

function processOptions()
{
    while [[ $# -gt 0 ]]
    do
        case "$1" in
            -s|--source)
                checkArgumentHasValue "$1" "$2"
                SOURCE="$2"
                shift
            ;;
            -d|--sample-data)
                checkArgumentHasValue "$1" "$2"
                if isInputNegative "$2"
                then
                    USE_SAMPLE_DATA=
                else
                    USE_SAMPLE_DATA="$2"
                fi
                shift
            ;;
            -e|--ee-path)
                # @DEPRECATED. Use --ee instead.
                checkArgumentHasValue "$1" "$2"
                EE_PATH="$2"
                INSTALL_EE=1
                shift
            ;;
            --ee)
                INSTALL_EE=1
            ;;
            --b2b)
                INSTALL_B2B=1
                if [[ "$2" =~ ^- ]]
                then
                    B2B_VERSION=
                else
                    B2B_VERSION="$2"
                    shift
                fi
            ;;
            -b|--git-branch)
                # @DEPRECATED. Use -v or --version instead
                checkArgumentHasValue "$1" "$2"
                MAGENTO_VERSION="$2"
                shift
            ;;
            -v|--version)
                checkArgumentHasValue "$1" "$2"
                MAGENTO_VERSION="$2"
                shift
            ;;
            --mode)
                checkArgumentHasValue "$1" "$2"
                MAGE_MODE=$2
                shift
            ;;
            -f|--force)
                FORCE=1
                USE_WIZARD=0
            ;;
            --websites)
              generateWebsites
              exit 0;
            ;;
            --quiet)
                VERBOSE=0
            ;;
            --skip-post-deploy)
                setRequest skipPostDeploy 1
            ;;
            -h|--help)
                printUsage
                exit;
            ;;
            --uninstall)
                uninstallAction
                exit;
            ;;
            --code-dump)
                checkArgumentHasValue "$1" "$2"
                setRequest codedump "$2"
                shift
            ;;
            --db-dump)
                checkArgumentHasValue "$1" "$2"
                setRequest dbdump "$2"
                shift
            ;;
            --restore-table)
                checkArgumentHasValue "$1" "$2"
                setRequest restoreTableName "$2"
                shift
            ;;
            --step)
                checkArgumentHasValue "$1" "$2"
                STEPS=($2)
                shift
                ;;
            --debug)
              set -o xtrace;
            ;;
            --php)
                checkArgumentHasValue "$1" "$2"
                BIN_PHP=$2
                shift
            ;;
            --remote-db)
                checkArgumentHasValue "$1" "$2"
                REMOTE_DB=$2
                shift
            ;;
            --es-host|--elasticsearch-host)
                checkArgumentHasValue "$1" "$2"
                ELASTICSEARCH_HOST=$2
                shift
            ;;
            --es-port|--elasticsearch-port)
                checkArgumentHasValue "$1" "$2"
                ELASTICSEARCH_PORT=$2
                shift
            ;;
        esac
        shift
    done
}

function cleanupCurrentDirectory()
{
  if [ "$(ls -A)" ] && askConfirmation "Current directory is not empty. Do you want to clean current Directory (y/N)"
  then
    CMD="ls -A | xargs rm -rf"
    runCommand
  fi
}

################################################################################
# Action Controllers
################################################################################
function magentoInstallAction()
{
    if [[ "${SOURCE}" ]]
    then
        cleanupCurrentDirectory
        addStep "downloadSourceCode"
    fi
    addStep "linkEnterpriseEdition"
    addStep "runComposerInstall"
    addStep "installMagento"
    if [[ "${USE_SAMPLE_DATA}" ]]
    then
        addStep "installSampleData"
    fi
    if [[ "$INSTALL_EE" ]] && [[ "$INSTALL_B2B" ]]
    then
        addStep "installB2B"
    fi
}

function magentoDeployDumpsAction()
{
    addStep "restore_code"
    addStep "configure_files"
    if [[ "$REMOTE_DB" ]]
    then
        addStep "add_remote"
    else
        addStep "restore_db"
        addStep "configure_db"
        addStep "validateDeploymentFromDumps"
    fi
}

function restoreTableAction()
{

    CMD="{ echo 'SET FOREIGN_KEY_CHECKS=0;';
       echo 'TRUNCATE ${DB_NAME}.$(getTablePrefix)$(getRequest restoreTableName);';
       zgrep 'INSERT INTO \`$(getRequest restoreTableName)\`' $(getDbDumpFilename); }
       | ${BIN_MYSQL} -h${DB_HOST} -u${DB_USER} --password=\"${DB_PASSWORD}\" --force $DB_NAME";
    runCommand
}

function magentoCustomStepsAction()
{
    prepareSteps
}

function generateWebsites()
{
  [ -z "$(getWebsites)" ] && echo "There is no additional websites" && return 0;
  prepareBaseURL
  [ ! -d websites ] && mkdir websites
  [ -f websites/index.php ] && rm websites/index.php
  for websiteCode in $(getWebsites)
  do
    local websiteDir="websites/${websiteCode}"
    createFileStructure "$websiteDir" && echo "Creating directory $websiteDir"
    updateWebsiteIndexFile "$websiteCode"
    createSymlinks "$websiteDir"

    local baseUrl="${BASE_URL}${websiteDir}/"
    generateWebsiteList "${websiteCode}" && echo "$baseUrl"
    updateWebsiteBaseUrls "${websiteCode}"
  done
  echo "Websites list: ${BASE_URL}websites/"
  ${BIN_PHP} bin/magento cache:flush -q && echo "Flushing cache"
}

function createSymlinks()
{
  local websiteDir="$1"
  [ ! -L "`pwd`/${websiteDir}/pub" ] && ln -s `pwd`/pub "`pwd`/${websiteDir}/pub"
}

function generateWebsiteList()
{
  local websiteCode="$1"
  local websiteDir="websites/${websiteCode}/";
  echo "<li><a href=\"${websiteCode}/\">${websiteDir}</a> (Store ID: $(getWebsiteIdByCode ${websiteCode}))</li>" >> websites/index.php
}

function updateWebsiteIndexFile()
{
  local websiteCode="$1"
  local websiteDir="websites/${websiteCode}";
  local codeLine='$_SERVER[\\Magento\\Store\\Model\\StoreManager::PARAM_RUN_CODE] = '"'${websiteCode}';";
  local typeLine='$_SERVER[\\Magento\\Store\\Model\\StoreManager::PARAM_RUN_TYPE] = '"'website';";
  sed -i "36 i ${codeLine}" "${websiteDir}/index.php"
  sed -i "37 i ${typeLine}" "${websiteDir}/index.php"
  sed -i "s/[\/]app[\/]bootstrap[.]php/\/..\/..\/app\/bootstrap.php/" "${websiteDir}/index.php"
}

function createFileStructure()
{
  local websiteDir="$1";
  [ ! -d "${websiteDir}" ] && mkdir "${websiteDir}";
  cp -f index.php "${websiteDir}/index.php"
}

function updateWebsiteBaseUrls()
{
  local websiteCode="$1"
  local websiteDir="websites/${websiteCode}";
    local baseUrl="${BASE_URL}${websiteDir}/"
    SQLQUERY="INSERT INTO ${DB_NAME}.$(getTablePrefix)core_config_data (config_id, scope, scope_id, path, value)
      SELECT NULL, 'websites' AS scope, website_id, 'web/unsecure/base_url' AS path, '${baseUrl}' AS new_url
      FROM ${DB_NAME}.$(getTablePrefix)store_website WHERE code = '${websiteCode}'
      ON DUPLICATE KEY UPDATE value = '${baseUrl}'"
    output="$(mysqlQuery)"
}

function getWebsites()
{
  local output=
  SQLQUERY="SELECT code FROM ${DB_NAME}.$(getTablePrefix)store_website WHERE website_id <> 0 AND is_default = 0";
  output="$(mysqlQuery)"
  echo "$output" | tail -n+3
}

function getWebsiteIdByCode()
{
  local websiteCode="$1"
  local output=
  SQLQUERY="SELECT website_id FROM ${DB_NAME}.$(getTablePrefix)store_website WHERE code = '${websiteCode}'";
  output="$(mysqlQuery)"
  echo "$output" | tail -n+3
}



################################################################################
# Tests
################################################################################

function assertEqual()
{
  local expected=${1:-}
  local current=${2:-}
  if [[ "$1" == "$2" ]]
  then
    echo -n "."
    return 0;
  else
    echo "===> Tests are failed."
    echo "Expected [${expected}] but current [${current}]"
    exit 1;
  fi
}

function runTests()
{
  echo "tests";
}

################################################################################
# Main
################################################################################

export LC_CTYPE=C
export LANG=C

function main()
{
    [[ $1 == "--test" ]] && runTests

    loadConfigFile $(getConfigFiles)
    processOptions "$@"
    initQuietMode
    printString Current Directory: "$(pwd)"
    printString "Configuration loaded from: $(getConfigFiles)"
    checkDependencies
    showWizard

    START_TIME=$(date +%s)
    if [[ "${STEPS[@]}" ]]
    then
        magentoCustomStepsAction;
    elif foundSupportBackupFiles
    then
        if getRequest restoreTableName
        then
            restoreTableAction
        else
            magentoDeployDumpsAction;
        fi
    else
        magentoInstallAction;
    fi
    addStep "afterInstall"
    executeSteps "${STEPS[@]}"

    END_TIME=$(date +%s)
    SUMMARY_TIME=$((((END_TIME - START_TIME)) / 60));
    printString "$(basename "$0") took $SUMMARY_TIME minutes to complete install/deploy process"

    printLine
    printString "${BASE_URL}"
    printString "${BASE_URL}${BACKEND_FRONTNAME}"
    printString "User: ${ADMIN_NAME}"
    printString "Pass: ${ADMIN_PASSWORD}"
    promptSaveConfig
}
main "${@}"
