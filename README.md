<img align="right" width="100" height="74" src="https://user-images.githubusercontent.com/8277210/183290025-d7b24277-dfb4-4ce1-bece-7fe0ecd5efd4.svg" />

# Actions Auto Discovery

This is a Bash script that automates the process of discovering and syncing GitHub Actions with Port. It uses the Port API to create new actions or update existing ones based on your GitHub Actions workflows.

### Prerequisites

Before running the script, you need to ensure that you have the following prerequisites installed on your system:

- `yq`
- `jq`
- `curl`

Also, you need to have the following information ready:

- `PORT_CLIENT_ID`: Your Port organization Client ID (required)
- `PORT_CLIENT_SECRET`: Your Port organization Client Secret (required)
- `GITHUB_TOKEN`: Your GitHub token with permissions to read contents + workflows (required)
- `GITHUB_ORG_NAME`: The name of the GitHub organization to sync with (required)
- `BLUEPRINT_IDENTIFIER`: The identifier of the blueprint to sync the actions into (required)
- `ACTION_TRIGGER`: CREATE/DAY-2/DELETE (optional, defaults to `CREATE`)

### Usage

```bash
#!/bin/bash
export PORT_CLIENT_ID="PORT_CLIENT_ID"
export PORT_CLIENT_SECRET="PORT_CLIENT_SECRET"
export GITHUB_TOKEN="GITHUB_TOKEN"
export GITHUB_ORG_NAME="GITHUB_ORG_NAME"
export BLUEPRINT_IDENTIFIER="BLUEPRINT_IDENTIFIER"
export ACTION_TRIGGER="TRIGGER" # optional, defaults to CREATE

curl -s https://raw.githubusercontent.com/port-labs/actions-auto-discovery/main/github-actions/sync.sh | bash
```

### How it works

1. It checks for the prerequisites mentioned above.
2. It checks the Port credentials by calling the Port API with the `PORT_CLIENT_ID` and `PORT_CLIENT_SECRET`.
3. It retrieves the access token from Port that is needed for API calls.
4. It retrieves a list of all the workflows in the specified GitHub organization using the GitHub API and prints their paths.
5. It then iterates through each repository in the organization and retrieves the workflows in each repository. 
6. It parses each workflow to find the inputs specified in the `workflow_dispatch` event and converts them to JSON.
7. It then creates a JSON object that describes the action and POSTs it to the Port API to either create a new action or update an existing one.

### Limitations

- This script only works for GitHub Actions workflows that use the `workflow_dispatch` event.
- The script can only sync actions with Port that have been triggered by the `workflow_dispatch` event.
