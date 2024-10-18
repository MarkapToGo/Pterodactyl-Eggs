#!/bin/bash
# shellcheck disable=SC2155
#
# CurseForge Installation Script
#
# Server Files: /mnt/server

: "${SERVER_DIR:=/mnt/server}"
: "${PROJECT_ID:=}"
: "${VERSION_ID:=}"
: "${API_KEY:=}"
: "${VELOCITY_SECRET_KEY:=}"

if [[ ! -d $SERVER_DIR ]]; then
    mkdir -p "$SERVER_DIR"
fi

if ! cd "$SERVER_DIR"; then
    echo -e "Failed to change directory to ${SERVER_DIR}"
    exit 1
fi

function install_required {
    echo -e "Installing required packages..."
    echo -e "\tRunning apt update"
    apt update > /dev/null 2>&1 || { echo "apt update failed!"; exit 1; }
    echo -e "\tRunning apt install"
    apt install -y wget jq unzip curl > /dev/null 2>&1 || { echo "apt install failed!"; exit 1; }
}

CURSEFORGE_API_URL="https://api.curseforge.com/v1/mods/"
CURSEFORGE_API_HEADERS=("--header=Accept: application/json" "--header=x-api-key: ${API_KEY}")

function get_download {
    echo -e "Retrieving CurseForge project information..."
    local PROJECT_DATA=$(wget -q "${CURSEFORGE_API_HEADERS[@]}" "${CURSEFORGE_API_URL}${PROJECT_ID}" -O -)
    local PROJECT_TITLE=$(echo "$PROJECT_DATA" | jq -r '.data.name // empty')

    if [[ -z "${PROJECT_DATA}" ]]; then
        echo -e "\tERROR: Failed to retrieve project data for project id '${PROJECT_ID}'"
        exit 1
    fi

    local IS_SERVER_PACK=false

    if [[ -z "${VERSION_ID}" || "${VERSION_ID}" == "latest" ]]; then
        echo -e "\tNo file ID specified, using latest file"
        VERSION_ID=$(echo "$PROJECT_DATA" | jq -r '.data.mainFileId // empty')

        local VERSION_SERVER_PACK="$(echo -e "${PROJECT_DATA}" | jq -r --arg VERSION_ID "$VERSION_ID" '.data.latestFiles[] | select(.id|tostring==$VERSION_ID) | .isServerPack')"
        local VERSION_SERVER_ID="$(echo -e "${PROJECT_DATA}" | jq -r --arg VERSION_ID "$VERSION_ID" '.data.latestFiles[] | select(.id|tostring==$VERSION_ID) | .serverPackFileId')"

        if [[ "${VERSION_SERVER_PACK}" == "false" && -n "${VERSION_SERVER_ID}" ]]; then
            echo -e "\tFound server pack file id '${VERSION_SERVER_ID}'"
            VERSION_ID=$VERSION_SERVER_ID
            IS_SERVER_PACK=true
        elif [[ "${VERSION_SERVER_PACK}" == "true" ]]; then
            IS_SERVER_PACK=true
        fi
    else
        echo -e "\tChecking if provided file id '${VERSION_ID}' exists"

        local FILE_DATA=$(wget -q "${CURSEFORGE_API_HEADERS[@]}" "${CURSEFORGE_API_URL}${PROJECT_ID}/files/${VERSION_ID}" -O -)

        if [[ -z "${FILE_DATA}" ]]; then
            echo -e "\tERROR: File id '${VERSION_ID}' not found for project '${PROJECT_TITLE}'"
            exit 1
        fi

        IS_SERVER_PACK=$(echo -e "${FILE_DATA}" | jq -r '.data.isServerPack // "false"')

        if [[ "${IS_SERVER_PACK}" == "false" ]]; then
            local VERSION_SERVER_PACK="$(echo -e "${FILE_DATA}" | jq -r '.data.serverPackFileId // empty')"
            if [[ -n "${VERSION_SERVER_PACK}" ]]; then
                echo -e "\tFound server pack file id '${VERSION_SERVER_PACK}'"
                VERSION_ID=$VERSION_SERVER_PACK
                IS_SERVER_PACK=true
            fi
        else
            IS_SERVER_PACK=true
        fi
    fi

    # Check if version id is unset or empty string
    if [[ -z "${VERSION_ID}" ]]; then
        echo -e "\tERROR: No file id found for project '${PROJECT_TITLE}'"
        exit 1
    fi

    if [[ "${IS_SERVER_PACK}" == "false" ]]; then
        echo -e "\tWARNING: File id '${VERSION_ID}' is not a server pack, attempting to use client files"
    fi

    # get json data to work with
    echo -e "\tRetrieving version information for '${VERSION_ID}'"
    local JSON_DATA=$(wget -q "${CURSEFORGE_API_HEADERS[@]}" "${CURSEFORGE_API_URL}${PROJECT_ID}/files/${VERSION_ID}/download-url" -O -)

    if [[ -z "${JSON_DATA}" ]]; then
        echo -e "\tERROR: Failed to retrieve file data for file id '${VERSION_ID}'"
        exit 1
    fi

    echo -e "\tParsing CurseForge pack download url"

    local DOWNLOAD_URL=$(echo -e "$JSON_DATA" | jq -r '.data // empty')
    if [[ -z "${DOWNLOAD_URL}" ]]; then
        echo -e "\tERROR: No download url found for file ${VERSION_ID}"
        exit 1
    fi

    # download modpack files
    echo -e "\tDownloading ${DOWNLOAD_URL}"
    if ! wget -q "${DOWNLOAD_URL}" -O server.zip; then
        echo -e "Download failed!"
        exit 1
    fi
}

function get_loader {
    echo -e "Retrieving loader information..."

    local PROJECT_DATA=$(wget -q "${CURSEFORGE_API_HEADERS[@]}" "${CURSEFORGE_API_URL}${PROJECT_ID}" -O -)
    local PROJECT_TITLE=$(echo "$PROJECT_DATA" | jq -r '.data.name // empty')
    if [[ -z "${PROJECT_DATA}" ]]; then
        echo -e "\tERROR: Failed to retrieve project data for project id '${PROJECT_ID}'"
        exit 1
    fi

    local FILE_DATA=$(wget -q "${CURSEFORGE_API_HEADERS[@]}" "${CURSEFORGE_API_URL}${PROJECT_ID}/files/${VERSION_ID}" -O -)

    if [[ -z "${FILE_DATA}" ]]; then
        echo -e "\tERROR: File id '${VERSION_ID}' not found for project '${PROJECT_TITLE}'"
        exit 1
    fi

    local IS_SERVER_PACK=$(echo -e "${FILE_DATA}" | jq -r '.data.isServerPack // "false"')
    local CLIENT_VERSION_ID;

    if [[ "${IS_SERVER_PACK}" == "true" ]]; then
        CLIENT_VERSION_ID="$(echo -e "${FILE_DATA}" | jq -r '.data.parentProjectFileId // empty')"
    else
        CLIENT_VERSION_ID=$VERSION_ID
    fi

    if [[ -z "${CLIENT_VERSION_ID}" ]]; then
        echo -e "\tERROR: File id '${VERSION_ID}' not found for project '${PROJECT_TITLE}'"
        exit 1
    fi

    echo -e "\tRetrieving file information for '${CLIENT_VERSION_ID}'"
    local JSON_DATA=$(wget -q "${CURSEFORGE_API_HEADERS[@]}" "${CURSEFORGE_API_URL}${PROJECT_ID}/files/${CLIENT_VERSION_ID}/download-url" -O -)

    echo -e "\tParsing CurseForge pack download url"

    local DOWNLOAD_URL=$(echo -e "$JSON_DATA" | jq -r '.data // empty')

    if [[ -z "${DOWNLOAD_URL}" ]]; then
        echo -e "\tERROR: No download url found for file id ${CLIENT_VERSION_ID}"
        exit 1
    fi

    # download modpack files
    echo -e "\tDownloading ${DOWNLOAD_URL}"
    wget -q "${DOWNLOAD_URL}" -O client.zip

    echo -e "\tUnpacking client manifest"
    unzip -jo client.zip manifest.json -d "${SERVER_DIR}"
    mv "${SERVER_DIR}/manifest.json" "${SERVER_DIR}/client.manifest.json" # rename to avoid conflicts with main manifest
    rm -rf client.zip

    echo -e "\tParsing client manifest"
    local MANIFEST="${SERVER_DIR}/client.manifest.json"

    LOADER_ID=$(jq -r '.minecraft.modLoaders[]? | select(.primary == true) | .id' "${MANIFEST}")
    LOADER_NAME=$(echo "${LOADER_ID}" | cut -d'-' -f1)
    LOADER_VERSION=$(echo "${LOADER_ID}" | cut -d'-' -f2)

    if [[ -z "${LOADER_NAME}" || -z "${LOADER_VERSION}" ]]; then
        echo -e "\tERROR: No loader found in client manifest!"
        exit 1
    fi

    MINECRAFT_VERSION=$(jq -r '.minecraft.version // empty' "${MANIFEST}")

    if [[ -z "${MINECRAFT_VERSION}" ]]; then
        echo -e "\tERROR: No minecraft version found in client manifest!"
        exit 1
    fi

    echo -e "\tFound loader ${LOADER_NAME} ${LOADER_VERSION} for Minecraft ${MINECRAFT_VERSION}"
}

function download_extra_mods {
    echo "Downloading extra mods..."

    local MODS_DIR="${SERVER_DIR}/mods"
    mkdir -p "${MODS_DIR}"

    local NEOFORWARDING_URL="https://cdn.modrinth.com/data/Vbdanw1l/versions/6dFFiwAQ/neoforwarding-1.2.0-1.21.X-NeoForge.jar"
    local WorldEdit_URL="https://cdn.modrinth.com/data/1u6JkXh5/versions/vBzkrSYP/worldedit-mod-7.3.6.jar"

    echo "Downloading NeoForwarding mod..."
    if ! wget -q -O "${MODS_DIR}/neoforwarding-1.0.0-1.21-NeoForge.jar" "${NEOFORWARDING_URL}"; then
        echo "Failed to download NeoForwarding mod."
        exit 1
    fi

    echo "Downloading WorldEdit mod..."
    if ! wget -q -O "${MODS_DIR}/worldedit-mod-7.3.6.jar" "${WorldEdit_URL}"; then
        echo "Failed to download World Edit mod."
        exit 1
    fi

    echo "Extra mods downloaded successfully."
}

function create_neoforwarding_config {
    local config_file="${SERVER_DIR}/config/neoforwarding-server.toml"
    echo "Creating neoforwarding-server.toml..."
    cat <<EOF > "$config_file"
# Use the 'forwarding.secret' from Velocity (and not the default value of '') and insert it here
forwardingSecret = "${VELOCITY_SECRET_KEY}"
# This must be enabled after you inserted your forwarding secret for the server to accept and send forwarding requests.
# If disabled the server will act as if the mod is not installed.
enableForwarding = true
EOF
    echo "neoforwarding-server.toml created successfully."
}

function unzip-strip() (
    set -u

    local archive=$1
    local destdir=${2:-}
    shift; shift || :
    echo -e "\tUnpacking ${archive} to ${destdir}"

    echo -e "\tCreating temporary directory"
    local tmpdir=/mnt/server/tmp
    if ! mkdir -p "${tmpdir}"; then
        echo -e "\tERROR: mkdir failed to create temporary directory"
        return 1
    fi

    trap 'rm -rf -- "$tmpdir"' EXIT

    echo -e "\tUnpacking archive"

    if ! unzip -q "$archive" -d "$tmpdir"; then
        echo -e "\tERROR: unzip failed to unpack archive"
        return 1
    fi

    echo -e "\tSetting glob settings"

    shopt -s dotglob

    echo -e "\tCleaning up directory structure"

    local files=("$tmpdir"/*) name i=1

    if (( ${#files[@]} == 1 )) && [[ -d "${files[0]}" ]]; then
        name=$(basename "${files[0]}")
        files=("$tmpdir"/*/*)
    else
        name=$(basename "$archive"); name=${archive%.*}
        files=("$tmpdir"/*)
    fi

    if [[ -z "$destdir" ]]; then
        destdir=./"$name"
    fi

    while [[ -f "$destdir" ]]; do
        destdir=${destdir}-$((i++));
    done

    echo -e "\tCopying files to ${destdir}"

    mkdir -p "$destdir"
    cp -ar "$@" -t "$destdir" -- "${files[@]}"
    rm -rf "$tmpdir"
)

function unpack_zip {
    echo -e "Unpacking server files..."
    unzip-strip server.zip "${SERVER_DIR}"
    rm -rf server.zip
}


function json_download_neoforge {
    echo "Downloading NeoForge..."

    local MC_VERSION=$MINECRAFT_VERSION
    local NEOFORGE_VERSION=$LOADER_VERSION

    # Remove spaces from the version number to avoid issues with curl
    NEOFORGE_VERSION="$(echo "$NEOFORGE_VERSION" | tr -d ' ')"
    MC_VERSION="$(echo "$MC_VERSION" | tr -d ' ')"

    if [[ ! -z ${NEOFORGE_VERSION} ]]; then
        if [[ ${NEOFORGE_VERSION} =~ 1\.20\.1- ]]; then
            DOWNLOAD_LINK="https://maven.neoforged.net/releases/net/neoforged/forge/${NEOFORGE_VERSION}/forge-${NEOFORGE_VERSION}"
            ARTIFACT_NAME="forge"
        else
            DOWNLOAD_LINK="https://maven.neoforged.net/releases/net/neoforged/neoforge/${NEOFORGE_VERSION}/neoforge-${NEOFORGE_VERSION}"
            ARTIFACT_NAME="neoforge"
        fi
    else
        if [[ ${MC_VERSION} =~ 1\.20\.1 ]]; then
            XML_DATA=$(curl -sSL https://maven.neoforged.net/releases/net/neoforged/forge/maven-metadata.xml)
            ARTIFACT_NAME="forge"
            NEOFORGE_OLD=1
        else
            XML_DATA=$(curl -sSL https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml)
            ARTIFACT_NAME="neoforge"
        fi

        REPO_URL="https://maven.neoforged.net/releases/net/neoforged/${ARTIFACT_NAME}/"

        if [[ ${MC_VERSION} =~ latest || ${MC_VERSION} == "" ]]; then
            echo "Getting latest version of NeoForge."
            MC_VERSION="1.$(echo -e ${XML_DATA} | xq -x '/metadata/versioning/release' | cut -d'.' -f1-2)"
        fi

        echo "Minecraft version: ${MC_VERSION}"

        if [[ -z "${NEOFORGE_OLD}" ]]; then
            VERSION_KEY=$(echo -n ${MC_VERSION} | cut -d'.' -f2-)
        else
            VERSION_KEY="${MC_VERSION}-"
        fi

        NEOFORGE_VERSION=$(echo -e ${XML_DATA} | xq -x "(/metadata/versioning/versions/*[starts-with(text(), '${VERSION_KEY}')])" | tail -n1)
        if [[ -z "${NEOFORGE_VERSION}" ]]; then
            echo "The install failed, because there is no valid version of NeoForge for the version of Minecraft selected."
            exit 1
        fi

        echo "NeoForge version: ${NEOFORGE_VERSION}"

        DOWNLOAD_LINK="${REPO_URL}${NEOFORGE_VERSION}/${ARTIFACT_NAME}-${NEOFORGE_VERSION}"
    fi

    echo "Downloading NeoForge version ${NEOFORGE_VERSION}"
    echo "Download link is ${DOWNLOAD_LINK}"

    if [[ ! -z "${DOWNLOAD_LINK}" ]]; then
        if curl --output /dev/null --silent --head --fail ${DOWNLOAD_LINK}-installer.jar; then
            echo -e "Installer jar download link is valid."
        else
            echo -e "Link is invalid. Exiting now"
            exit 2
        fi
    else
        echo -e "No download link provided. Exiting now"
        exit 3
    fi

    local INSTALLER_JAR="neoforge-${NEOFORGE_VERSION}-installer.jar"
    local INSTALLER_LOG="installer.jar.log"

    curl -s -o ${INSTALLER_JAR} -sS ${DOWNLOAD_LINK}-installer.jar

    if [[ ! -f ./${INSTALLER_JAR} ]]; then
        echo "!!! Error downloading NeoForge version ${NEOFORGE_VERSION} !!!"
        exit 4
    fi

    rm -rf libraries/net/neoforged/${ARTIFACT_NAME}
    rm unix_args.txt

    echo -e "Installing NeoForge server.\n"
    if ! java -jar ${INSTALLER_JAR} --installServer > ${INSTALLER_LOG} 2>&1; then
        echo -e "\nInstall failed using NeoForge version ${NEOFORGE_VERSION} and Minecraft version ${MINECRAFT_VERSION}."
        exit 5
    fi

    ln -sf libraries/net/neoforged/${ARTIFACT_NAME}/*/unix_args.txt unix_args.txt

    echo -e "Deleting ${INSTALLER_JAR} and ${INSTALLER_LOG} files.\n"
    rm -rf ${INSTALLER_JAR} ${INSTALLER_LOG}

    echo "Installation process is completed!"
}

function create_stylelabor_js {
    local script_dir="${SERVER_DIR}/kubejs/server_scripts/StyleLabor"
    local script_file="${script_dir}/stylelabor.js"

    # Ensure the directory exists
    mkdir -p "$script_dir"

    # Create the stylelabor.js file
    echo "Creating stylelabor.js..."
    cat <<EOF > "$script_file"
ServerEvents.recipes((e) => {
  let makeID = (type, output, input) => {
    return _makeID('mekanism', type, output, input);
  };

  let metallurgic_infusing = (output, input, chem, perTick) => {
    e.recipes.mekanism.metallurgic_infusing(output, input, chem, perTick ? perTick : false).id(makeID('metallurgic_infusing', output, input));
  };

  // StyleLabor Uraninite Recipe
  metallurgic_infusing('powah:uraninite_raw', 'modern_industrialization:uranium_ingot', '40x mekanism:diamond');
});
EOF
    echo "stylelabor.js created successfully."
}

function clean_mods_folder {
    local MODS_DIR="${SERVER_DIR}/mods"
    if [[ -d "${MODS_DIR}" ]]; then
        echo "Deleting existing mods folder..."
        rm -rf "${MODS_DIR}"
    fi
}

clean_mods_folder
install_required

if [[ -z "${PROJECT_ID}" ]]; then
    echo "ERROR: You must specify a PROJECT_ID environment variable!"
    exit 1
fi

if [[ ! "${PROJECT_ID}" = "zip" ]]; then
    get_download
fi

get_loader
unpack_zip

if [[ -f "${SERVER_DIR}/manifest.json" ]]; then
    echo "Found manifest.json, installing mods"
    json_download_mods
    json_download_overrides
fi

if [[ -f "${SERVER_DIR}/client.manifest.json" ]]; then
    MANIFEST="${SERVER_DIR}/client.manifest.json"

    if [[ $LOADER_NAME == "neoforge" ]]; then
        json_download_neoforge
    fi
fi

# Create eula.txt to accept the EULA
echo "eula=true" > "${SERVER_DIR}/eula.txt"

# Run the startserver.sh script to install all mods and complete the setup
if [[ -f "${SERVER_DIR}/startserver.sh" ]]; then
    echo "Running startserver.sh to complete the setup..."
    chmod +x "${SERVER_DIR}/startserver.sh"
    "${SERVER_DIR}/startserver.sh"
else
    echo "ERROR: startserver.sh not found in ${SERVER_DIR}"
    exit 1
fi

# Download extra mods
download_extra_mods

# Download extra mods
download_extra_mods

# Create neoforwarding-server.toml
create_neoforwarding_config

# Create stylelabor.js
create_stylelabor_js

echo -e "\nInstall completed successfully, enjoy!"