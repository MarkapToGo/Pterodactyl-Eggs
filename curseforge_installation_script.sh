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

function json_download_mods {
    echo "Downloading mods..."

    local MANIFEST="${SERVER_DIR}/manifest.json"
    jq -c '.files[]? | select(.required == true) | {project: .projectID, file: .fileID}' "${MANIFEST}" | while read -r mod; do
        local MOD_PROJECT_ID=$(echo "${mod}" | jq -r '.project // empty')
        local MOD_FILE_ID=$(echo "${mod}" | jq -r '.file // empty')

        if [[ -z "${MOD_PROJECT_ID}" || -z "${MOD_FILE_ID}" ]]; then
            echo -e "\tERROR: Failed to parse project id or file id for mod '${mod}'"
            exit 1
        fi

        local FILE_URL=$(wget -q "${CURSEFORGE_API_HEADERS[@]}" "${CURSEFORGE_API_URL}${MOD_PROJECT_ID}/files/${MOD_FILE_ID}/download-url" -O - | jq -r '.data // empty')

        if [[ -z "${FILE_URL}" ]]; then
            echo -e "\tERROR: No download url found for mod ${MOD_PROJECT_ID} ${MOD_FILE_ID}"
            exit 1
        fi

        echo -e "\tDownloading ${FILE_URL}"

        if ! wget -q "${FILE_URL}" -P "${SERVER_DIR}/mods"; then
            echo -e "\tERROR: Failed to download mod ${MOD_PROJECT_ID} ${MOD_FILE_ID}"
            exit 1
        fi
    done
}

function json_download_overrides {
    echo "Copying overrides..."
    if [[ -d "${SERVER_DIR}/overrides" ]]; then
        cp -r "${SERVER_DIR}/overrides/"* "${SERVER_DIR}"
        rm -r "${SERVER_DIR}/overrides"
    fi
}

FORGE_INSTALLER_URL="https://maven.minecraftforge.net/net/minecraftforge/forge/"

function json_download_forge {
    echo "Downloading Forge..."

    local MC_VERSION=$MINECRAFT_VERSION
    local FORGE_VERSION=$LOADER_VERSION

    FORGE_VERSION="${MC_VERSION}-${FORGE_VERSION}"
    if [[ "${MC_VERSION}" == "1.7.10" || "${MC_VERSION}" == "1.8.9" ]]; then
        FORGE_VERSION="${FORGE_VERSION}-${MC_VERSION}"
    fi

    local FORGE_JAR="forge-${FORGE_VERSION}.jar"
    if [[ "${MC_VERSION}" == "1.7.10" ]]; then
        FORGE_JAR="forge-${FORGE_VERSION}-universal.jar"
    fi

    local FORGE_URL="${FORGE_INSTALLER_URL}${FORGE_VERSION}/forge-${FORGE_VERSION}"

    echo -e "\tUsing Forge ${FORGE_VERSION} from ${FORGE_URL}"

    local FORGE_INSTALLER="${FORGE_URL}-installer.jar"
    echo -e "\tDownloading Forge Installer ${FORGE_VERSION} from ${FORGE_INSTALLER}"

    if ! wget -q -O forge-installer.jar "${FORGE_INSTALLER}"; then
        echo -e "\tERROR: Failed to download Forge Installer ${FORGE_VERSION}"
        exit 1
    fi

    # Remove old Forge files so we can safely update
    rm -rf libraries/net/minecraftforge/forge/
    rm -f unix_args.txt

    echo -e "\tInstalling Forge Server ${FORGE_VERSION}"
    if ! java -jar forge-installer.jar --installServer > /dev/null 2>&1; then
        echo -e "\tERROR: Failed to install Forge Server ${FORGE_VERSION}"
        exit 1
    fi

    if [[ $MC_VERSION =~ ^1\.(17|18|19|20|21|22|23) || $FORGE_VERSION =~ ^1\.(17|18|19|20|21|22|23) ]]; then
        echo -e "\tDetected Forge 1.17 or newer version. Setting up Forge Unix arguments"
        ln -sf libraries/net/minecraftforge/forge/*/unix_args.txt unix_args.txt
    else
        mv "$FORGE_JAR" forge-server-launch.jar
        echo "forge-server-launch.jar" > ".serverjar"
    fi

    rm -f forge-installer.jar
}

FABRIC_INSTALLER_URL="https://meta.fabricmc.net/v2/versions/installer"

function json_download_fabric {
    echo "Downloading Fabric..."

    local MC_VERSION=$MINECRAFT_VERSION
    local FABRIC_VERSION=$LOADER_VERSION

    local INSTALLER_JSON=$(wget -q -O - ${FABRIC_INSTALLER_URL} )
    local INSTALLER_VERSION=$(echo "$INSTALLER_JSON" | jq -r '.[0].version // empty')
    local INSTALLER_URL=$(echo "$INSTALLER_JSON" | jq -r '.[0].url // empty')

    if [[ -z "${INSTALLER_VERSION}" ]]; then
        echo -e "\tERROR: No Fabric installer version found"
        exit 1
    fi

    if [[ -z "${INSTALLER_URL}" ]]; then
        echo -e "\tERROR: No Fabric installer url found"
        exit 1
    fi

    echo -e "\tDownloading Fabric Installer ${MC_VERSION}-${FABRIC_VERSION} (${INSTALLER_VERSION}) from ${INSTALLER_URL}"

    if ! wget -q -O fabric-installer.jar "${INSTALLER_URL}"; then
        echo -e "\tERROR: Failed to download Fabric Installer ${MC_VERSION}-${FABRIC_VERSION} (${INSTALLER_VERSION})"
        exit 1
    fi

    echo -e "\tInstalling Fabric Server ${MC_VERSION}-${FABRIC_VERSION} (${INSTALLER_VERSION})"
    if ! java -jar fabric-installer.jar server -mcversion "${MC_VERSION}" -loader "${FABRIC_VERSION}" -downloadMinecraft; then
        echo -e "\tERROR: Failed to install Fabric Server ${MC_VERSION}-${FABRIC_VERSION} (${INSTALLER_VERSION})"
        exit 1
    fi

    echo "fabric-server-launch.jar" > ".serverjar"

    rm -f fabric-installer.jar
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

QUILT_INSTALLER_URL="https://meta.quiltmc.org/v3/versions/installer"

function json_download_quilt {
    echo "Downloading Quilt..."

    local MC_VERSION=$MINECRAFT_VERSION
    local QUILT_VERSION=$LOADER_VERSION

    local INSTALLER_JSON=$(wget -q -O - ${QUILT_INSTALLER_URL} )
    local INSTALLER_VERSION=$(echo "$INSTALLER_JSON" | jq -r '.[0].version // empty')
    local INSTALLER_URL=$(echo "$INSTALLER_JSON" | jq -r '.[0].url // empty')

    if [[ -z "${INSTALLER_VERSION}" ]]; then
        echo -e "\tERROR: No Quilt installer version found"
        exit 1
    fi

    if [[ -z "${INSTALLER_URL}" ]]; then
        echo -e "\tERROR: No Quilt installer URL found"
        exit 1
    fi

    echo -e "\tDownloading Quilt Installer ${MC_VERSION}-${QUILT_VERSION} (${INSTALLER_VERSION}) from ${INSTALLER_URL}"

    if ! wget -q -O quilt-installer.jar "${INSTALLER_URL}"; then
        echo -e "\tERROR: Failed to download Quilt Installer ${MC_VERSION}-${QUILT_VERSION} (${INSTALLER_VERSION})"
        exit 1
    fi

    echo -e "\tInstalling Quilt Server ${MC_VERSION}-${QUILT_VERSION} (${INSTALLER_VERSION})"
    if ! java -jar quilt-installer.jar install server "${MC_VERSION}" "${QUILT_VERSION}" --download-server --install-dir=./; then
        echo -e "\tERROR: Failed to install Quilt Server ${MC_VERSION}-${QUILT_VERSION} (${INSTALLER_VERSION})"
        exit 1
    fi

    echo "quilt-server-launch.jar" > ".serverjar"

    rm quilt-installer.jar
}

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

    if [[ $LOADER_NAME == "forge" ]]; then
        json_download_forge
    fi

    if [[ $LOADER_NAME == "fabric" ]]; then
        json_download_fabric
    fi

    if [[ $LOADER_NAME == "quilt" ]]; then
        json_download_quilt
    fi

    if [[ $LOADER_NAME == "neoforge" ]]; then
        json_download_neoforge
    fi
fi

echo -e "\nInstall completed successfully, enjoy!"