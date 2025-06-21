#!/bin/bash

#########################################################
# create_labels.sh
#
# Purpose:
#   Reads a comma-separated text file and creates key:value label pairs for a Longbow tenant via API.
#   The first item in each row is the label key; subsequent items are the values.
#
# Usage:
#   Ensure the API KEY is set in your .rc file:
#     - e.g.: export KEY="lb-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
#   Ensure the TENANT_ID is set in the script:
#     - e.g.: TENANT_ID="con_xxxxxxxxxxxxxx"
#   Place your input file (labels.txt) in the same directory as this script, formatted as:
#     key1,value1,value2
#     key2,value3
#   You can also pass the label list file as an argument to the script or use the default variable in the script:
#     - e.g.: ./create_labels.sh /path/to/your/labels.txt
#
# Requirements:
#   - bash shell (zsh array functions work differently, so we need to use bash)
#   - curl
#
# Limitations:
#   - Does not check for all disallowed special characters in keys/values
#   - Does not add values to existing keys nor set default values for a label
#   - Always sets 'manage values' and 'values required' to false
#   - Skips label creation if the label key already exists
#
#########################################################

# uncomment this tocheck for errors and exit if they occur
# set -euo pipefail

# Source the correct shell config to load KEY
shell=$(ps -p $$ -o comm=)
if [ "$shell" = "/bin/bash" ]; then
    #echo "Running in bash"
    source ~/.bashrc
else
    echo "Running in $shell, exiting"
    exit 1
fi

if [ -z "$KEY" ]; then
    echo ""
    echo "Error: KEY environment variable is not set. Please set it in your shell config." >&2
    echo 'Add a line to your shell config like this: export KEY="lb-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"'
    echo ""
    exit 1
fi

# Stage API Key
CURL_KEY="X-API-KEY: $KEY"

SCRIPT_DIR="$(dirname "$0")"

# Default label list file
DEFAULT_LABEL_LIST="$SCRIPT_DIR/labels.txt"

TENANT_ID="con_xxxxxxxxxxxxxx"

# uncomment the BASE_URL that you want to use
BASE_URL="api.longbow.security"
# BASE_URL="api.eu.longbow.security"


# Use first argument as label list if provided, else use default
if [ $# -ge 1 ]; then
    LABEL_LIST="$1"
else
    LABEL_LIST="$DEFAULT_LABEL_LIST"
fi

# Check if the file exists
if [ ! -f "$LABEL_LIST" ]; then
    echo ""
    echo "Label list file not found: $LABEL_LIST"
    echo ""
    exit 1
fi

create_labels() {
    REST_CREATE_LABELS="https://$BASE_URL:443/v1/labels"
    response=$(curl -s -w "%{http_code}" -o /tmp/label_response.json --location "$REST_CREATE_LABELS" \
        --header "X-Alta-Tenant: $TENANT_ID" \
        --header 'Content-Type: application/json' \
        --header "$CURL_KEY" \
        --data "$payload")
    if [[ "$response" != "200" && "$response" != "201" ]]; then
        echo "Failed to create label $label_key. HTTP status: $response"
        cat /tmp/label_response.json
    fi
}

# error checking for this CURL function is in the main loop
label_key_exists() {
    REST_NAME_VALID="https://$BASE_URL:443/v1/labels/name-valid?key=$1"
    curl -s --location "$REST_NAME_VALID" \
        --header "X-Alta-Tenant: $TENANT_ID" \
        --header 'Content-Type: application/json' \
        --header "$CURL_KEY"
}

echo ""

main() {
    # split the list on commas and create an array
    local IFS="," 
    local -a item_array=($1) 
    unset IFS 

    # return the zero-th item in the array
    # the script assumes that the first item in the array is the label key
    label_key="${item_array[0]}"

    # get rid of the key and only keep the label values
    item_array=("${item_array[@]:1}")

    # put all of the values into the correct format for the payload
    values="["
    for item in "${item_array[@]}"; do
        values+="{\"value\":\"$item\"},"
    done
    values="${values%,}]"

    # assemble the payload for the curl command
    payload="{ \"key\": \"$label_key\", \"type\": \"VERACODE\", \"description\": \"\", \"availableValues\": $values, \"settings\": { \"valueRequired\": false, \"valuesManagement\": false }}"

    # If the key does not exist then create it and all of its labels
    key_check_result=$(label_key_exists "$label_key")
    if [[ "$key_check_result" == "true" ]]; then
        create_labels
        echo "CREATED KEY: $label_key"
        echo "CREATED LABELS: $values"
        echo ""
    elif [[ "$key_check_result" == "false" ]]; then
        echo "Key already exists: $label_key"
    else
        echo "ERROR -- We did not get back true or false from the key check. The response was:"
        echo ""
        echo "$key_check_result"
        echo ""
    fi
    echo ""
}

# The second test condition is needed if the file is only one line without a newline character
while IFS= read -r line || [[ -n $line ]]; do

    # The following three lines are for debugging
        # separator=","
        # count=$(awk -v sep="$separator" '{print split($0, a, sep)}' <<< "$line")
        # echo "$count items to process"

    # check for unprintable characters and remove them, then remove spaces and repeated commas from the line
    line=$(echo "$line" | xargs | tr -cd '\11\12\15\40-\176' | sed -e 's/\ //g' -e 's/,,/,/g')

    main "$line"

done < "$LABEL_LIST"

echo ""

exit 0