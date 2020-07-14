#!/usr/bin/env bash
# This script will install a systemd service and timer to mount a remote ftp share, rsync a directory to it, and then unmount the share
# I'm using this to sync photos to a digital picture frame
#
# Copyright (c) 2020 Bryan Roessler <bryanroessler@gmail.com>
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
version="0.1"
debug="off" # turn "on" for debugging
# IMPORTANT OPTIONS #
service_name="rsync-to-picture-frame" # use something specific and memorable
description="Mount picture frame ftp share and rsync syncthing picture_frame directory to it" # a short description
ftp_share="192.168.1.100:2221" # source share, best to make this a static address if you can
source_dir="$HOME/Pictures/picture_frame" # source files from this directory
# Less important options
user="$(id -un)" # default run as current user
user_id="$(id -u)" # default run as current user
group_id="$(id -g)" # default run as current user
script_dir="$PWD" # where to copy the script to, default is $PWD (created automatically if missing)
mount_dir="/media/picture_frame_ftp" # directory to mount the ftp share to (created automatically if missing)
temp_dir="/tmp/picture_frame_ftp" # ftp does not support rsync temp files (created automatically if missing)
# Service settings
service_dir="$HOME/.config/systemd/user"
on_calendar="hourly" # how often to mount and sync
# END USER OPTIONS #

# if debug is on, echo additional output
debug() { [[ $debug == "on" ]] && echo "debug: $*"; }

check_and_install() {
  if ! command -v "$1" > /dev/null 2>&1; then
    echo "Installing $1"
    [[ -f /etc/os-release ]] && source /etc/os-release
    if [[ "${NAME,,}" =~ (fedora|centos) ]]; then
      debug "sudo dnf install -y $1"
      if ! sudo dnf install -y "$1"; then
        echo "Could not install $1, exiting"
        exit 1
      fi
    elif [[ "${NAME,,}" =~ (debian|ubuntu) ]]; then
      debug "sudo apt install -y $1"
      if ! sudo apt install -y "$1"; then
        echo "Could not install $1, exiting"
        exit 1
      fi
    else
      echo "$1 must be installed"
      exit 1
    fi
  fi
  return $?
}

# Happily make directories
mk_dir() {
  for DIR in "$@"; do
    if [[ ! -d "$DIR" ]]; then
      debug "mkdir -p $DIR"
      if ! mkdir -p "$DIR"; then
        debug "sudo mkdir -p $DIR"
        if ! sudo mkdir -p "$DIR"; then
          echo "sudo mkdir $DIR failed, exiting"
          exit 1
        fi
      fi
    fi
  done
}

# Happily chown directories as $user
chown_dir() {
  for DIR in "$@"; do
    debug "chown $user:$user -R $DIR"
    if ! chown "$user":"$user" -R "$DIR"; then
      debug "sudo chown $user:$user -R $DIR"
      if ! sudo chown "$user":"$user" -R "$DIR"; then
        echo "sudo chown on $DIR failed, exiting"
        exit 1
      fi
    fi
  done
  return $?
}

# Happily make files executable
make_exec() {
  for FILE in "$@"; do
    debug "chmod a+x $FILE"
    if ! chmod a+x "$FILE"; then
      debug "sudo chmod a+x $FILE"
      if ! sudo chmod a+x "$FILE"; then
        echo "sudo chmod on $FILE failed, exiting"
        exit 1
      fi
    fi
  done
  return $?
}     

# Happily copy files
cp_file() {
  if [[ ! -f "$1" ]]; then
    echo "$1 is missing"
    exit 1
  elif ! cp -af "$1" "$2"; then
    echo "failed, retrying with sudo"
    debug "sudo cp -f $1 $2"
    if ! sudo cp -af "$1" "$2"; then
      echo "Copying script failed, exiting"
      exit 1
    fi
  fi
}

# Use sed to find ($1) and replace ($2) a string in a file ($3)
f_and_r() {
  debug "s#$1#$2#" "$3"
  if ! sed -i "s#$1#$2#g" "$3"; then
    exit 1
  fi
}

main() {

  # Install curlftps
  debug "check_and_install curlftpfs"
  check_and_install "curlftpfs"

  # Disable existing timer
  debug "systemctl --user disable --now $service_name.timer"
  systemctl --user disable --now "$service_name.timer" &> /dev/null
  
  # Unmount existing ftp share
  mountpoint -q -- "$mount_dir" && fusermount -u "$mount_dir"

  # Create directories
  mk_dir "$source_dir" "$mount_dir" "$service_dir" "$script_dir"
  chown_dir "$source_dir" "$mount_dir" "$service_dir" "$script_dir"

  # Copy script file
  cp_file "original.sh" "$script_dir/$service_name.sh"
  make_exec "$script_dir/$service_name.sh"
  f_and_r "{{mount_dir}}" "$mount_dir" "$script_dir/$service_name.sh"
  f_and_r "{{source_dir}}" "$source_dir" "$script_dir/$service_name.sh"
  f_and_r "{{ftp_share}}" "$ftp_share" "$script_dir/$service_name.sh"
  f_and_r "{{user_id}}" "$user_id" "$script_dir/$service_name.sh"
  f_and_r "{{group_id}}" "$group_id" "$script_dir/$service_name.sh"
  f_and_r "{{temp_dir}}" "$temp_dir" "$script_dir/$service_name.sh"
  
  # Copy service file
  cp_file "original.service" "$service_dir/$service_name.service"
  f_and_r "{{path_to_script}}" "$script_dir/$service_name.sh" "$service_dir/$service_name.service"
  f_and_r "{{description}}" "$script_dir/$service_name.sh" "$service_dir/$service_name.service"

  # Copy timer file
  cp_file "original.timer" "$service_dir/$service_name.timer"
  f_and_r "{{on_calendar}}" "$on_calendar" "$service_dir/$service_name.timer"
  f_and_r "{{description}}" "$description" "$service_dir/$service_name.timer"

  # Enable timer
  debug "systemctl --user daemon-reload"
  systemctl --user daemon-reload
  debug "systemctl --user enable --now $service_name.timer"
  systemctl --user enable --now "$service_name.timer"
}

main "$@"
exit $?
