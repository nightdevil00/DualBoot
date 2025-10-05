#!/bin/bash

# Start the ssh-agent in the background
eval "$(ssh-agent -s)"

# Add your SSH key to the ssh-agent
# You will be prompted for your passphrase here
ssh-add /home/mihai/.ssh/id_ed25519

# Pull changes from the remote repository
git pull --rebase origin main

# Push your changes to GitHub
git push -u origin main
