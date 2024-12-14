#!/bin/bash
# FTB Pack Installation Script # Install script for FTB modpacks using the FTB modpacks API.
#
# Server Files: /mnt/server
if [ ! -d /mnt/server ]; then
    mkdir -p /mnt/server
fi
cd /mnt/server

# Download needed software.
function install_required {
    apt update
    apt install -y curl jq
}

function get_modpack_id {
    urlencode() {
        local string="${1// /%20}"
        echo "$string"
    }

    # if no modpack id is set and modpack search term is set.
    if [ -z ${FTB_MODPACK_ID} ] && [ ! -z "${FTB_SEARCH_TERM}" ]; then
        encoded_search_term=$(urlencode "$FTB_SEARCH_TERM")
        JSON_DATA=$(curl -sSL https://api.modpacks.ch/public/modpack/search/8?term="${encoded_search_term}")

        # grabs the first modpack in array.
        FTB_MODPACK_ID=$(echo -e ${JSON_DATA} | jq -r ".packs[0]")
    fi

    if [ -z ${FTB_MODPACK_VERSION_ID} ] && [ ! -z ${FTB_VERSION_STRING} ]; then
        # grabs the correct version id matching the string.
        FTB_MODPACK_VERSION_ID=$(curl -sSL https://api.modpacks.ch/public/modpack/${FTB_MODPACK_ID} | jq -r --arg VSTRING ${FTB_VERSION_STRING} '.versions[] | select(.name == $VSTRING) | .id')
    fi
}

function run_installer {
    # get architecture for installer
    INSTALLER_TYPE=$([ "$(uname -m)" == "x86_64" ] && echo "linux" || echo "arm/linux")
    echo "ModpackID: ${FTB_MODPACK_ID} VersionID: ${FTB_MODPACK_VERSION_ID} InstallerType: ${INSTALLER_TYPE}"

    # download installer
    curl -L https://api.modpacks.ch/public/modpack/0/0/server/${INSTALLER_TYPE} --output serversetup
    chmod +x ./serversetup

    # remove old forge files (to allow updating)
    rm -rf libraries/net/minecraftforge/forge
    rm -rf libraries/net/neoforged
    rm -f unix_args.txt

    # run installer
    ./serversetup ${FTB_MODPACK_ID} ${FTB_MODPACK_VERSION_ID} --auto --noscript --nojava
}

function install_specified_forge_version {
    if [[ -n "${SPECIFIED_FORGE_VERSION}" ]]; then
        echo "Removing old NeoForge version..."
        rm -rf libraries/net/neoforged
        rm -f unix_args.txt

        echo "Installing specified NeoForge version ${SPECIFIED_FORGE_VERSION}..."
        DOWNLOAD_LINK="https://maven.neoforged.net/releases/net/neoforged/neoforge/${SPECIFIED_FORGE_VERSION}/neoforge-${SPECIFIED_FORGE_VERSION}-installer.jar"
        curl -s -o neoforge-installer.jar ${DOWNLOAD_LINK}

        if [[ ! -f ./neoforge-installer.jar ]]; then
            echo "!!! Error downloading NeoForge version ${SPECIFIED_FORGE_VERSION} !!!"
            exit 4
        fi

        java -jar neoforge-installer.jar --installServer
        ln -sf libraries/net/neoforged/forge/*/unix_args.txt unix_args.txt
        rm -f neoforge-installer.jar
    fi
}

# allows startup command to work
function move_startup_files {
    # create symlink for forge unix_args.txt if exists
    if compgen -G "libraries/net/minecraftforge/forge/*/unix_args.txt"; then
        ln -sf libraries/net/minecraftforge/forge/*/unix_args.txt unix_args.txt
    fi

    # create symlink for neoforge unix_args.txt if exists
    if compgen -G "libraries/net/neoforged/forge/*/unix_args.txt"; then
        ln -sf libraries/net/neoforged/forge/*/unix_args.txt unix_args.txt
    fi

    # move forge/neoforge/fabric jar file to start-server.jar if exists
    if compgen -G "forge-*.jar"; then
        mv -f forge-*.jar start-server.jar
    elif compgen -G "fabric-*.jar"; then
        mv -f fabric-*.jar start-server.jar
    fi
}

# installer cleanup
function installer_cleanup {
    rm serversetup
    rm -f run.bat
    rm -f run.sh
    rm -f neoforge-installer.jar.log
}

# run installation steps
install_required
get_modpack_id
run_installer
install_specified_forge_version
move_startup_files
installer_cleanup

echo "Finished installing FTB modpack"