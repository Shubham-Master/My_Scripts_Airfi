#!/bin/bash

# Navigate to the airserver repository
cd ~/MI-Group/airserver || { echo "Repository not found!"; exit 1; }

# Define the target folder that will be used
folder_name="D`evops_Scripts`"

# Create the folder only if it doesn't exisst
if [ ! -d "$folder_name" ]; then
  mkdir "$folder_name"
  echo "Folder '$folder_name' created."
fi

# Copy files to the target folder
cp -r ~/path_to_your_files/* "$folder_name" || { echo "File copy failed!"; exit 1; }

# Check for uncommitted changes
git status --porcelain | grep . > /dev/null
if [ $? -ne 0 ]; then
  echo "No changes to commit. Exiting."
  exit 0
fi

# Pull the latest changes
git pull origin main

# Add all files
git add .

# Commit the changes with a timestamp
commit_message="Auto-update_Dev_scripts: $(date '+%Y-%m-%d %H:%M:%S')"
git commit -m "$commit_message"

# Push the changes
git push origin main

echo "Files pushed successfully!"
