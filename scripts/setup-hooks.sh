#!/usr/bin/env bash
set -e
HOOKS_PATH="hooks"

# Ensure the script is run from a relative context
function validateRelativeContext() {
    if [ ! -d "./scripts" ]; then
        printf "\033[0m \033[97;101mWARNING\033[0m: This script should be executed relative from the project root, e.g. \033[93m./scripts/setup-hooks.sh\033[0m.\n"
        exit 1
    fi
}

# Opt-in to Git Hooks, if needed.
function optInToGitHooksIfNeeded() {
    local gitHooksPath=${1:-"hooks"}

    # Check if we have a Git Hooks directory.
    if [ ! -d "$gitHooksPath" ]
    then
        # We don't have a Git Hooks directory. If necessary, opt-out to using Git Hooks.
        git config core.hooksPath > /dev/null

        if [[ $? -eq 0 ]]
        then
            printf "\033[93m*)\033[0m Opt-out to using Git Hooks\033[94m\n"
            git config --unset core.hooksPath
        fi

        return
    fi

    # Check if we need to opt-in or opt-out to using Git Hooks.
    if [[ $(git config core.hooksPath) != "$gitHooksPath" ]]
    then
        printf "\033[93m*)\033[0m Opt-in to using Git Hooks\033[0m\n"
        git config core.hooksPath $gitHooksPath
    elif [[ $(git config core.hooksPath) == "$gitHooksPath" ]]
    then
        printf "\033[93m*)\033[0m Already opted-in to using Git Hooks\033[0m\n"
    else
        printf "\033[93m*)\033[0m Skip opting-in to using Git Hooks\033[0m\n"
    fi
}

# Validate we are being executed relatively fron the project root.
validateRelativeContext
# Configure Git hooks, if needed.
optInToGitHooksIfNeeded "$HOOKS_PATH"