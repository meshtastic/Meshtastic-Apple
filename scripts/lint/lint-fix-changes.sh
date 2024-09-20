#!/bin/bash

# Path to swiftlint
SWIFT_LINT=$(which swiftlint)

# Check if SwiftLint is installed
if [[ -e "${SWIFT_LINT}" ]]; then
    count=0
    for file_path in $(git ls-files -m --exclude-from=.gitignore | grep ".swift$"); do
        export SCRIPT_INPUT_FILE_$count=$file_path
        count=$((count + 1))
    done

    ##### Check for modified files in unstaged/Staged area #####
    for file_path in $(git diff --name-only --cached | grep ".swift$"); do
        export SCRIPT_INPUT_FILE_$count=$file_path
        count=$((count + 1))
    done

    ##### Make the count available as global variable #####
    export SCRIPT_INPUT_FILE_COUNT=$count

    ##### Fix files or exit if no files found for fixing #####
    if [ "$count" -ne 0 ]; then
        echo "Found files to fix! Running swiftLint --fix..."

        # Run SwiftLint --fix on each file
        for ((i = 0; i < count; i++)); do
            file_var="SCRIPT_INPUT_FILE_$i"
            file_path=${!file_var}
            echo "Fixing $file_path"
            $SWIFT_LINT --fix "$file_path"
        done

        # Add the fixed files back to staging
        for ((i = 0; i < count; i++)); do
            file_var="SCRIPT_INPUT_FILE_$i"
            file_path=${!file_var}
            git add "$file_path"
        done

        echo "swiftLint --fix completed and files re-staged."

        # Optionally lint the fixed files
        echo "Linting fixed files..."
        $SWIFT_LINT lint --use-script-input-files
    else
        exit 0
    fi

    RESULT=$?

    if [ $RESULT -eq 0 ]; then
        exit 0
    else
        echo ""
        echo "⛔️ Violation found of the type ERROR! Please fix these issues before continuing!"
    fi
    exit $RESULT

else
    echo "SwiftLint not installed. Please install from https://github.com/realm/SwiftLint"
    exit -1
fi
