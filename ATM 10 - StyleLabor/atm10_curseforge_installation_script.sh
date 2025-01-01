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

function download_extra_mods {
    echo "Downloading extra mods..."

    local MODS_DIR="${SERVER_DIR}/mods"
    mkdir -p "${MODS_DIR}"

    local NEOFORWARDING_URL="https://cdn.modrinth.com/data/Vbdanw1l/versions/tdpr4TRc/neoforwarding-1.3.0-1.21.X-NeoForge.jar"
    local WorldEdit_URL="https://cdn.modrinth.com/data/1u6JkXh5/versions/vBzkrSYP/worldedit-mod-7.3.6.jar"
    local LOGBEGONE_URL="https://cdn.modrinth.com/data/9ON3zv6e/versions/1CpHwmQd/logbegone-neo-1.21-1.0.2.jar"

    local DYNVIEW_URL="https://www.curseforge.com/api/v1/mods/366140/files/5570957/download"
    local Chunksending_URL="https://www.curseforge.com/api/v1/mods/831663/files/5540768/download"
    local BetterChunks_URL="https://www.curseforge.com/api/v1/mods/899487/files/5747092/download"

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

    echo "Downloading Log Begone mod..."
    if ! wget -q -O "${MODS_DIR}/logbegone-neo-1.21-1.0.2.jar" "${LOGBEGONE_URL}"; then
        echo "Failed to download Log Begone mod."
        exit 1
    fi

    echo "[PERFORMANCE MOD] Downloading Dynview mod..."
    if ! wget -q -O "${MODS_DIR}/dynview.jar" "${DYNVIEW_URL}"; then
        echo "Failed to download Dynview mod."
        exit 1
    fi

    echo "[PERFORMANCE MOD] Downloading Chunksending mod..."
    if ! wget -q -O "${MODS_DIR}/chunksending.jar" "${Chunksending_URL}"; then
        echo "Failed to download Chunksending mod."
        exit 1
    fi

    echo "[PERFORMANCE MOD] Downloading BetterChunks mod..."
    if ! wget -q -O "${MODS_DIR}/betterchunks.jar" "${BetterChunks_URL}"; then
        echo "Failed to download BetterChunks mod."
        exit 1
    fi
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

function create_stylelabor_js {
    local script_dir="${SERVER_DIR}/kubejs/server_scripts/StyleLabor"
    local script_file="${script_dir}/stylelabor.js"


    # Ensure the directory exists
    mkdir -p "$script_dir"


    # Create the stylelabor.js file
    echo "Creating stylelabor.js..."
    cat <<EOF > "$script_file"
// priority: 100

ServerEvents.recipes((e) => {
	e.remove({ output: 'industrialforegoing:infinity_nuke' });
e.remove({ output: 'industrialforegoing:infinity_nuke' });
});

EOF
    echo "stylelabor.js created successfully."
}


function add_stylelabor_file {
    local CONFIG_DIR="${SERVER_DIR}/config/ftbquests/quests/chapters"
    local FILE_PATH="${CONFIG_DIR}/stylelabor.snbt"

    echo "Adding stylelabor.snbt file..."

    mkdir -p "${CONFIG_DIR}"

    cat > "${FILE_PATH}" <<EOL
{
	default_hide_dependency_lines: false
	default_quest_shape: "rsquare"
	filename: "stylelabor"
	group: ""
	icon: {
		components: {
			"productivebees:gene_group": {
				attribute: "productivity"
				purity: 100
				value: "productivity.medium"
			}
		}
		id: "productivebees:gene"
	}
	id: "7327DDFA32F13FDE"
	images: [
		{
			height: 2.0d
			image: "modern_industrialization:block/bronze_tank"
			rotation: 0.0d
			width: 2.0d
			x: -0.5d
			y: -1.5d
		}
		{
			height: 1.0d
			image: "modern_industrialization:item/high_pressure_water_bucket"
			rotation: -15.0d
			width: 1.0d
			x: -0.75d
			y: -1.5d
		}
		{
			height: 1.0d
			image: "the_bumblezone:item/honey_bucket"
			rotation: 0.0d
			width: 1.0d
			x: -0.5d
			y: -1.5d
		}
		{
			height: 1.0d
			image: "undergarden:item/virulent_mix_bucket"
			order: -1
			rotation: 15.0d
			width: 1.0d
			x: -0.3d
			y: -1.5d
		}
		{
			height: 1.0d
			image: "minecraft:textures/entity_icon/wandering_trader.png"
			rotation: 0.0d
			width: 1.0d
			x: 3.0d
			y: -1.5d
		}
		{
			height: 2.0d
			image: "modern_industrialization:block/aluminum_tank"
			rotation: 0.0d
			width: 2.0d
			x: 3.0d
			y: -1.5d
		}
		{
			height: 1.0d
			image: "integrateddynamics:aspect/write/double/effect/particle"
			rotation: 0.0d
			width: 1.0d
			x: 3.5d
			y: -2.0d
		}
	]
	order_index: 3
	quest_links: [ ]
	quests: [
		{
			icon: {
				id: "mekanism:brine_bucket"
			}
			id: "7863395A0E5C7B3F"
			rewards: [{
				id: "2A0B8043D4499DDD"
				item: {
					components: {
						"mekanism:fluids": {
							fluid_tanks: [{
								amount: 2147483647
								id: "mekanism:brine"
							}]
						}
					}
					count: 1
					id: "mekanism:creative_fluid_tank"
				}
				type: "item"
			}]
			tasks: [
				{
					consume_items: true
					count: 20000L
					id: "1F14FF6BCED502A7"
					item: { count: 1, id: "mekanism:thermal_evaporation_block" }
					type: "item"
				}
				{
					consume_items: true
					count: 5000L
					id: "5405DCFB5603A776"
					item: { count: 1, id: "mekanism:thermal_evaporation_controller" }
					type: "item"
				}
				{
					consume_items: true
					count: 1000L
					id: "24E7A5E998F56186"
					item: { count: 1, id: "mekanism:ultimate_mechanical_pipe" }
					type: "item"
				}
				{
					consume_items: true
					count: 512L
					id: "5397B6176040FCAC"
					item: { count: 1, id: "mekanism:ultimate_fluid_tank" }
					type: "item"
				}
			]
			x: -1.5d
			y: 0.0d
		}
		{
			icon: {
				id: "mekanism:lithium_bucket"
			}
			id: "386D5A7E39587927"
			rewards: [{
				id: "0C12E1A72E494AEE"
				item: {
					components: {
						"mekanism:fluids": {
							fluid_tanks: [{
								amount: 2147483647
								id: "mekanism:lithium"
							}]
						}
					}
					count: 1
					id: "mekanism:creative_fluid_tank"
				}
				type: "item"
			}]
			tasks: [
				{
					consume_items: true
					count: 20000L
					id: "3D5DAAEAF0D2ED22"
					item: { count: 1, id: "mekanism:thermal_evaporation_block" }
					type: "item"
				}
				{
					consume_items: true
					count: 5000L
					id: "238D6C598F836D0E"
					item: { count: 1, id: "mekanism:thermal_evaporation_controller" }
					type: "item"
				}
				{
					consume_items: true
					count: 1000L
					id: "15A9E00E7F7E8015"
					item: { count: 1, id: "mekanism:ultimate_mechanical_pipe" }
					type: "item"
				}
				{
					consume_items: true
					count: 512L
					id: "7568A2F32C966835"
					item: { count: 1, id: "mekanism:ultimate_fluid_tank" }
					type: "item"
				}
			]
			x: 0.5d
			y: 0.0d
		}
		{
			icon: {
				id: "mekanism:heavy_water_bucket"
			}
			id: "18D10D694533DEBF"
			rewards: [{
				id: "726DB0B92565CD5A"
				item: {
					components: {
						"mekanism:fluids": {
							fluid_tanks: [{
								amount: 2147483647
								id: "mekanism:heavy_water"
							}]
						}
					}
					count: 1
					id: "mekanism:creative_fluid_tank"
				}
				type: "item"
			}]
			tasks: [
				{
					consume_items: true
					count: 10000L
					id: "30B7FEBA6A3F1308"
					item: { count: 1, id: "mekanism:ultimate_mechanical_pipe" }
					type: "item"
				}
				{
					consume_items: true
					count: 25000L
					id: "5C55EE06104C4BC8"
					item: { count: 1, id: "mekanism:electric_pump" }
					type: "item"
				}
				{
					consume_items: true
					count: 5000L
					id: "5A9DC1F63A493011"
					item: { count: 1, id: "minecraft:bucket" }
					type: "item"
				}
				{
					consume_items: true
					count: 1024L
					id: "2F858DD41A566E30"
					item: { count: 1, id: "mekanism:ultimate_fluid_tank" }
					type: "item"
				}
				{
					consume_items: true
					count: 1024L
					id: "418C33EA2927DE19"
					item: { count: 1, id: "minecraft:water_bucket" }
					type: "item"
				}
			]
			x: -0.5d
			y: 0.0d
		}
		{
			can_repeat: true
			icon: {
				id: "alltheores:raw_uranium"
			}
			id: "46F86E4EE855C4B9"
			rewards: [{
				id: "443162A668E66637"
				item: {
					count: 1
					id: "mysticalagriculture:uranium_seeds"
				}
				type: "item"
			}]
			tasks: [
				{
					consume_items: true
					count: 4L
					id: "7FD0DAE819403822"
					item: { count: 1, id: "alltheores:uranium_block" }
					type: "item"
				}
				{
					consume_items: true
					count: 4L
					id: "4440B42307068A00"
					item: { count: 4, id: "mysticalagriculture:imperium_block" }
					type: "item"
				}
				{
					consume_items: true
					id: "7462C0B908D3B1AD"
					item: { count: 1, id: "mysticalagriculture:prosperity_seed_base" }
					type: "item"
				}
			]
			x: 3.0d
			y: 0.0d
		}
	]
}

EOL

    echo "stylelabor.snbt file added successfully."
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

download_extra_mods
add_stylelabor_file

# Create stylelabor.js
create_stylelabor_js

echo -e "\nInstall completed successfully, enjoy!"