#!/bin/bash
set -e

#########################################################################################################################################################
# Description:
#   This script is responsible for automatically discovering and syncing GitHub Actions with Port.
# 
# Variables:
#   PORT_CLIENT_ID - Your Port organization Client ID (required)
#   PORT_CLIENT_SECRET - Your Port organization Client Secret (required)
#   GITHUB_TOKEN - Your GitHub token (required)
#   GITHUB_ORG_NAME - The name of the GitHub organization to sync with (required)
#   BLUEPRINT_IDENTIFIER - The identifier of the blueprint to sync with (required)
#   ACTION_TRIGGER - The trigger to use when syncing actions (optional, default: CREATE)
#   REPO_LIST - A list of repositories to sync with (optional, default: all repositories in the organization `*`)
#########################################################################################################################################################

# Global variables
REPO_BRANCH=${REPO_BRANCH:-"main"}
REPO_BASE_URL="https://raw.githubusercontent.com/port-labs/template-assets/${REPO_BRANCH}"
COMMON_FUNCTIONS_URL="${REPO_BASE_URL}/common.sh"
TRIGGER="${ACTION_TRIGGER:-"CREATE"}"
REPO_LIST="${REPO_LIST:-"*"}"

# Create temporary folder
function cleanup {
  rm -rf "${temp_dir}"
}

trap cleanup EXIT

temp_dir=$(mktemp -d)

echo "Importing common functions..."
curl -s ${COMMON_FUNCTIONS_URL} -o "${temp_dir}/common.sh"
source "${temp_dir}/common.sh"

echo "Checking for prerequisites..."
check_commands "yq" "jq" "curl"
check_port_credentials "${PORT_CLIENT_ID}" "${PORT_CLIENT_SECRET}"

access_token=$(curl -s --location --request POST 'https://api.getport.io/v1/auth/access_token' --header 'Content-Type: application/json' --data-raw "{
    \"clientId\": \"${PORT_CLIENT_ID}\",
    \"clientSecret\": \"${PORT_CLIENT_SECRET}\"
}" | jq -r '.accessToken')


echo "Syncing GitHub Actions with Port..."
# Define pagination variables
page=1
per_page=100
has_more=true

while [[ $has_more == true ]]; do
  # Retrieve a page of repositories
  repositories=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/orgs/$GITHUB_ORG_NAME/repos?page=$page&per_page=$per_page" | jq -r '.[].name')

  # Check if there are more repositories to retrieve
  if [[ $(echo "$repositories" | wc -l) -lt $per_page ]]; then
    has_more=false
  else
    ((page++))
  fi

  IFS=',' read -ra REPO_LIST_ARRAY <<< "$REPO_LIST"

  # Loop over each repository
  for repo_name in $repositories; do
    # Check if the repository is part of the REPO_LIST
    if [[ ${#REPO_LIST_ARRAY[@]} -gt 0 ]] && [[ ! " ${REPO_LIST_ARRAY[@]} " =~ " $repo_name " ]] && [[ $REPO_LIST != "*" ]]; then
      echo "Skipping $repo_name as it is not part of the REPO_LIST..."
      continue
    fi

    # Retrieve workflows for the repository
    workflows=$(curl -s -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/json" "https://api.github.com/repos/$GITHUB_ORG_NAME/$repo_name/actions/workflows?page=$page&per_page=$per_page" | jq -r '.workflows[].path')

    # Loop over each workflow
    for file_path in $workflows; do
      echo "Syncing $repo_name/$file_path..."

      # Download the workflow file
      input_yaml_file="$temp_dir/workflow.yaml"
      output_file="$temp_dir/output.json"

      URL="https://api.github.com/repos/$GITHUB_ORG_NAME/$repo_name/contents/$file_path"
      echo "Downloading $URL..."

      response_code=$(curl -w "%{http_code}" -s -o /dev/null -H "Authorization: token $GITHUB_TOKEN" "$URL")

      if [[ ${response_code} == "404" ]]; then
          echo "Error: $i returned a 404 status code. Exiting loop."
          continue
      fi

      curl -s -H "Authorization: token $GITHUB_TOKEN" "$URL" | jq -r '.content' | base64 -d > $input_yaml_file

      if ! yq -e '.on.workflow_dispatch' $input_yaml_file >/dev/null 2>&1; then
        echo "yq didn't find workflow_dispatch section in $input_yaml_file. Skipping..."
        continue
      fi

      yq -i '.on.workflow_dispatch.inputs' $input_yaml_file

      echo "Parsing workflow_dispatch.inputs to JSON"
      cat $input_yaml_file
      yq eval -j $input_yaml_file > $output_file

      if [[ $(cat $output_file) == "null" ]]; then
        echo "No workflow_dispatch.inputs found. putting an empty object at the action.json file..."
        echo "{}" > $output_file
      fi


      jq_filter='{
        "identifier": "'$repo_name'-'$(basename $file_path .yaml)'",
        "title": "'$repo_name' '$(basename $file_path .yaml)'",
        "trigger": "'$TRIGGER'",
        "invocationMethod": {
          "type": "GITHUB",
          "org": "'$GITHUB_ORG_NAME'",
          "repo": "'$repo_name'",
          "workflow": "'$(basename $file_path .yaml)'",
          "omitPayload": true
        },
        "userInputs": {
          "properties": map_values({
          "description": (.description // null),
          "type": (.type | if . == "choice" then "string" else . end),
          "default": (.default // null),
          "enum": (.options // null)
        } | with_entries(select(.value != null))),
          "required": [to_entries[] | select(.value.required == true) | .key]
        }
      }'

      jq "$jq_filter" "$output_file" > $temp_dir/action.json

      echo "Syncing action.json to Port..."
      cat $temp_dir/action.json

      curl --location -X POST "https://api.getport.io/v1/blueprints/$BLUEPRINT_IDENTIFIER/actions" \
        --header "Authorization: Bearer $access_token" \
        --header "Content-Type: application/json" \
        --data-raw "$(cat $temp_dir/action.json)"
    done
  done
done 

