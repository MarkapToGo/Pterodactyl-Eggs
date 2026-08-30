#!/bin/ash
# Velocity Proxy Installation Script
#
# Server Files: /mnt/server

PROJECT="velocity"
USER_AGENT="pterodactyl-installer/1.0 (pterodactyl.io)"
API_BASE="https://fill.papermc.io/v3/projects/${PROJECT}"

# Ensure required packages exist
if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    apk add --no-cache curl jq
fi

: "${SERVER_DIR:=/mnt/server}"
: "${VELOCITY_VERSION:=latest}"
: "${BUILD_NUMBER:=latest}"
: "${SERVER_JARFILE:=velocity.jar}"

cd "${SERVER_DIR}" || exit 1

if [ -n "${DL_PATH}" ]; then
    echo -e "Using supplied download url: ${DL_PATH}"
    DOWNLOAD_URL=$(eval echo $(echo "${DL_PATH}" | sed -e 's/{{\/${/g' -e 's/}}/}/g'))
else
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "${TMP_DIR}"' EXIT

    echo -e "Fetching version list for ${PROJECT}..."
    if ! curl -sSL -H "User-Agent: ${USER_AGENT}" "${API_BASE}" -o "${TMP_DIR}/project.json"; then
        echo -e "ERROR: Failed to connect to PaperMC API (${API_BASE})"
        exit 1
    fi

    if [ ! -s "${TMP_DIR}/project.json" ] || jq -e '.ok == false' "${TMP_DIR}/project.json" >/dev/null 2>&1; then
        echo -e "ERROR: Failed to fetch valid project metadata for ${PROJECT}"
        exit 1
    fi

    LATEST_VERSION=$(jq -r '.versions | to_entries | map(.value) | flatten | .[0] // empty' "${TMP_DIR}/project.json")

    if [ -z "${VELOCITY_VERSION}" ] || [ "${VELOCITY_VERSION}" = "latest" ]; then
        RESOLVED_VERSION="${LATEST_VERSION}"
        echo -e "Using latest ${PROJECT} version: ${RESOLVED_VERSION}"
    else
        MATCHED_VERSION=$(jq -r --arg V "${VELOCITY_VERSION}" '.versions | to_entries | map(.value) | flatten | map(select(. == $V or (. | contains($V)))) | .[0] // empty' "${TMP_DIR}/project.json")
        if [ -n "${MATCHED_VERSION}" ]; then
            RESOLVED_VERSION="${MATCHED_VERSION}"
            echo -e "Version is valid. Using version: ${RESOLVED_VERSION}"
        else
            echo -e "Version '${VELOCITY_VERSION}' not found, falling back to latest version: ${LATEST_VERSION}"
            RESOLVED_VERSION="${LATEST_VERSION}"
        fi
    fi

    echo -e "Fetching build information for ${PROJECT} version ${RESOLVED_VERSION}..."
    BUILDS_URL="${API_BASE}/versions/${RESOLVED_VERSION}/builds"
    if ! curl -sSL -H "User-Agent: ${USER_AGENT}" "${BUILDS_URL}" -o "${TMP_DIR}/builds.json"; then
        echo -e "ERROR: Failed to connect to builds endpoint (${BUILDS_URL})"
        exit 1
    fi

    if [ ! -s "${TMP_DIR}/builds.json" ] || jq -e '.ok == false' "${TMP_DIR}/builds.json" >/dev/null 2>&1; then
        echo -e "ERROR: Failed to fetch builds for version ${RESOLVED_VERSION}"
        exit 1
    fi

    BUILD_FILTER='(map(select((.id | tostring) == $B)) | .[0]) // .[0]'

    RESOLVED_BUILD=$(jq -r --arg B "${BUILD_NUMBER}" "${BUILD_FILTER} | .id // empty" "${TMP_DIR}/builds.json")
    DOWNLOAD_URL=$(jq -r --arg B "${BUILD_NUMBER}" "${BUILD_FILTER} | .downloads | to_entries[0].value.url // empty" "${TMP_DIR}/builds.json")
    JAR_NAME=$(jq -r --arg B "${BUILD_NUMBER}" "${BUILD_FILTER} | .downloads | to_entries[0].value.name // empty" "${TMP_DIR}/builds.json")
    CHECKSUM_SHA256=$(jq -r --arg B "${BUILD_NUMBER}" "${BUILD_FILTER} | .downloads | to_entries[0].value.checksums.sha256 // empty" "${TMP_DIR}/builds.json")

    if [ -z "${DOWNLOAD_URL}" ]; then
        echo -e "ERROR: Could not resolve download URL for ${PROJECT} ${RESOLVED_VERSION} build ${RESOLVED_BUILD}"
        exit 1
    fi

    echo -e "Version being downloaded:"
    echo -e "Velocity Version:  ${RESOLVED_VERSION}"
    echo -e "Build:             ${RESOLVED_BUILD}"
    echo -e "JAR Name of Build: ${JAR_NAME}"
fi

echo -e "Downloading ${JAR_NAME:-Velocity JAR}..."
if [ -f "${SERVER_JARFILE}" ]; then
    echo -e "Backing up existing ${SERVER_JARFILE} to ${SERVER_JARFILE}.old"
    mv "${SERVER_JARFILE}" "${SERVER_JARFILE}.old"
fi

echo -e "Running: curl -sSL -H 'User-Agent: ${USER_AGENT}' -o ${SERVER_JARFILE} ${DOWNLOAD_URL}"
if ! curl -sSL -H "User-Agent: ${USER_AGENT}" -o "${SERVER_JARFILE}" "${DOWNLOAD_URL}"; then
    echo -e "ERROR: Failed to download server jar file!"
    exit 1
fi

if [ -n "${CHECKSUM_SHA256}" ] && command -v sha256sum >/dev/null 2>&1; then
    echo -e "Verifying SHA256 checksum..."
    DOWNLOADED_SHA256=$(sha256sum "${SERVER_JARFILE}" | awk '{print $1}')
    if [ "${DOWNLOADED_SHA256}" = "${CHECKSUM_SHA256}" ]; then
        echo -e "Checksum verification succeeded!"
    else
        echo -e "WARNING: Checksum mismatch! Expected ${CHECKSUM_SHA256}, got ${DOWNLOADED_SHA256}"
    fi
fi

if [ -f velocity.toml ]; then
    echo -e "velocity config file exists"
else
    echo -e "downloading velocity config file template..."
    curl -sSL https://raw.githubusercontent.com/parkervcp/eggs/master/game_eggs/minecraft/proxy/java/velocity/velocity.toml -o velocity.toml
fi

if [ -f forwarding.secret ]; then
    echo -e "velocity forwarding secret file already exists"
else
    echo -e "creating forwarding secret file..."
    touch forwarding.secret
    date +%s | sha256sum | base64 | head -c 12 > forwarding.secret
fi

echo -e "install complete"
