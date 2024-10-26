#!/bin/bash

CONFIG_PATH=/data/options.json

TOKEN=$(jq --raw-output ".oauth_access_token" $CONFIG_PATH)
OUTPUT_DIR=$(jq --raw-output ".output // empty" $CONFIG_PATH)
KEEP_LAST=$(jq --raw-output ".keep_last // empty" $CONFIG_PATH)
FILETYPES=$(jq --raw-output ".filetypes // empty" $CONFIG_PATH)

if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="/"
fi

echo "[Info] Files will be uploaded to: ${OUTPUT_DIR}"

echo "[Info] Saving OAUTH_ACCESS_TOKEN to /etc/uploader.conf"
echo "OAUTH_ACCESS_TOKEN=${TOKEN}" >> /etc/uploader.conf

echo "[Info] Listening for messages via stdin service call..."

# listen for input
while read -r msg; do
    # parse JSON
    echo "$msg"
    cmd="$(echo "$msg" | jq --raw-output '.command')"
    echo "[Info] Received message with command ${cmd}"
    if [[ $cmd = "upload" ]]; then
        echo "[Info] Uploading all .tar files in /backup (skipping those already in :qx)"
        ./dropbox_uploader.sh -s -f /etc/uploader.conf upload /backup/*.tar "$OUTPUT_DIR"
        if [[ "$KEEP_LAST" ]]; then
            echo "[Info] keep_last option is set, cleaning up files..."
            python3 /keep_last.py "$KEEP_LAST"

            # Retrieve all filenames in the directory, using the config file
            ALL_FILES=($(/dropbox_uploader.sh -f /etc/uploader.conf list "$DROPBOX_DIR" | tail -n +2 | awk '{print $3}'))

            # Select the latest $KEEP_LAST files (last $KEEP_LAST entries in the list)
            LATEST_FILES=('${ALL_FILES[@]: -$KEEP_LAST}')

            # Create a list of files to delete (all files except the latest 10)
            FILES_TO_DELETE=()
            for file in "${ALL_FILES[@]}"; do
                if [[ ! " ${LATEST_FILES[@]} " =~ " ${file} " ]]; then
                    FILES_TO_DELETE+=("$file")
                fi
            done

            # Delete the older files, using the config file
            for FILE in "${FILES_TO_DELETE[@]}"; do
            #    ./dropbox_uploader.sh -f /etc/uploader.conf delete "$DROPBOX_DIR/$FILE"
            echo "Going to delete $DROPBOX_DIR/$FILE"
            done
        fi
        if [[ "$FILETYPES" ]]; then
            echo "[Info] filetypes option is set, scanning share directory for files with extensions ${FILETYPES}"
            find /share -regextype posix-extended -regex "^.*\.(${FILETYPES})" -exec ./dropbox_uploader.sh -s -f /etc/uploader.conf upload {} "$OUTPUT_DIR" \;
        fi
    else
        # received undefined command
        echo "[Error] Command not found: ${cmd}"
    fi
done
