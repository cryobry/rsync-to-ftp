#!/usr/bin/env bash
debug="off" # turn "on" for debugging
# IMPORTANT OPTIONS #
frame_address="192.168.1.100:2221" # you can find this on the frame, best to make static
source_dir="$HOME/Pictures/picture_frame" # source pictures directory

# Less important options
user="$(whoami)" # default run as current user
user_id="$(id -u)"
group_id="$(id -g)"
script_dir="$PWD" # where to copy the script to, default is $PWD
dest_dir="/media/picture_frame_ftp" # the ftp mount path
temp_dir="/tmp/picture_frame_ftp" # ftp does not support rsync temp files
# Service settings
service_dir="$HOME/.config/systemd/user"
service_name="rsync-to-picture-frame"
on_calendar="hourly"
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
  mountpoint -q -- "$dest_dir" && fusermount -u "$dest_dir"

  # Create directories
  mk_dir "$source_dir" "$dest_dir" "$service_dir" "$script_dir"
  chown_dir "$source_dir" "$dest_dir" "$service_dir" "$script_dir"

  # Copy script file
  cp_file "$service_name.sh.original" "$script_dir/$service_name.sh"
  make_exec "$script_dir/$service_name.sh"
  f_and_r "{{ftp_mount_path}}" "$dest_dir" "$script_dir/$service_name.sh"
  f_and_r "{{source_dir}}" "$source_dir" "$script_dir/$service_name.sh"
  f_and_r "{{frame_address}}" "$frame_address" "$script_dir/$service_name.sh"
  f_and_r "{{user_id}}" "$user_id" "$script_dir/$service_name.sh"
  f_and_r "{{group_id}}" "$group_id" "$script_dir/$service_name.sh"
  f_and_r "{{temp_dir}}" "$temp_dir" "$script_dir/$service_name.sh"
  
  # Copy service file
  cp_file "$service_name.service.original" "$service_dir/$service_name.service"
  f_and_r "{{path_to_script}}" "$script_dir/$service_name.sh" "$service_dir/$service_name.service"

  # Copy timer file
  cp_file "$service_name.timer.original" "$service_dir/$service_name.timer"
  f_and_r "{{on_calendar}}" "$on_calendar" "$service_dir/$service_name.timer"

  # Enable timer
  debug "systemctl --user daemon-reload"
  systemctl --user daemon-reload
  debug "systemctl --user enable --now $service_name.timer"
  systemctl --user enable --now "$service_name.timer"
}

main "$@"
exit $?
