#!/usr/bin/env bash
# This script will mount mom's photo frame ftp share locally
# Use install.sh to change settings

# if the mount already exists, unmount it
mountpoint -q -- "{{mount_dir}}" && fusermount -u "{{mount_dir}}"

# make temp directory (ftp does not support rsync temp files)
[[ ! -d "{{temp_dir}}" ]] && mkdir -p "{{temp_dir}}"

# Mount it and rsync over the photos
if curlftpfs -o uid="{{user_id}}",gid="{{group_id}}" "{{frame_address}}" "{{mount_dir}}"; then
  if ! rsync -r --delete --quiet --temp-dir="{{temp_dir}}" "{{source_dir}}/" "{{mount_dir}}"; then
    echo "rsync -r --delete --quiet {{source_dir}}/ {{mount_dir}} failed!"
    exit 1
  fi
  if ! fusermount -u "{{mount_dir}}"; then
    echo "Could not unmount {{mount_dir}}"
    exit 1
  fi
else
  echo "Could not mount Mom's picture frame"
  if ping -c 1 "{{frame_address}}"; then
    echo "Ping OK, check the photo frame settings or the filesystem"
    exit 1
  else
    echo "Could not ping the photo frame, is it on?"
    exit 1
  fi
fi

exit $?
