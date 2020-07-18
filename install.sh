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
# SOFT

rsync-ftp-timer() {

  version="0.2"
  #debug="true" # enable for debugging
  [[ -v debug ]] && echo "Debugging on"
  # IMPORTANT OPTIONS #
  name="rsync-to-picture-frame" # use something specific and memorable
  description="Mount picture frame ftp share and rsync syncthing picture_frame directory to it" # a short description
  ftp_share="192.168.1.100:2221" # source share, best to make this a static address if you can
  source_dir="$HOME/Pictures/picture_frame" # source files from this directory
  # Less important options
  user="$(id -un)" # default run as current user
  user_id=$(id -u "$user")
  group=$(id -gn "$user") # default use group of current user
  group_id=$(id -g "$user")
  script_dir="$PWD" # where to copy the script to, default is $PWD (created automatically if missing)
  mount_dir="/media/$name" # directory to mount the ftp share to (created automatically if missing)
  temp_dir="/tmp/name" # ftp does not support rsync temp files (created automatically if missing)
  # Service settings
  service_dir="$HOME/.config/systemd/user"
  on_calendar="hourly" # how often to mount and sync
  # END USER OPTIONS #

  print_help_and_exit() {

    debug "Running: ${FUNCNAME[0]}"

    cat <<-'EOF'
USAGE
install.sh [[OPTION] [VALUE]]...

EXAMPLE
./install.sh \
  -n "rsync-to-picture-frame" \
  -d "Mount picture frame ftp share and rsync syncthing picture_frame directory to it" \
  -f "192.168.1.102:2221" \
  -s "$HOME/Pictures/picture_frame"

OPTIONS
  --name, -n
    Name of the service
  --description, -d
    Description of the service
  --ftp-share, -f
    The destination address of the ftp share to sync to (ex. 192.168.1.100:2221)
  --source-dir, -s
    The source directory to sync from
  --user, -u
    The user to run the service as (default: the current user)
  --install-dir, -i
    The location to install the script to (default: $PWD)
  --mount-dir, -m
    The location to mount the ftp share (default: /media/name)
  --temp-dir, -t
    The location of the temp directory (default: /tmp/name)
    Note: FTP does not support rsync temp files so we must use a local temp dir
  --service-dir
    The location of the service directory (default: $HOME/.config/systemd/user)
  --on-calendar
    The systemd OnCalendar command (default: hourly)
  --version, -v
      Print this script version and exit
  --debug
      Print debug output
  --help, -h
      Print help dialog and exit
  --uninstall
      Completely uninstall the named service and remove associated directories
EOF

    # Exit using passed exit code
    [[ -z $1 ]] && exit 0 || exit "$1"
  }


  parse_input() {

    debug "Running: ${FUNCNAME[0]}"

    if _input=$(getopt -o +n:d:f:s:u:i:m:t:vhu -l name:,description:,ftp-share:,source-dir:,user:,install-dir:,mount-dir:,temp-dir:,service-dir:,on-calendar:,version,debug,help,uninstall -- "$@"); then
      eval set -- "$_input"
      while true; do
        case "$1" in
          --name|-n)
            shift && name="$1"
            ;;
          --description|-d)
            shift && declare -g description="$1"
            ;;
          --ftp-share|-f)  
            shift && declare -g ftp_share="$1"
            ;;
          --source-dir|-s)
            shift && declare -g source_dir="$1"
            ;;
          --user|-u)
            shift && \
              declare -g user user_id group group_id && \
              user="$1" && user_id=$(id -u "$user") && \
              group=$(id -gn "$user") && group_id=$(id -g "$user")
            ;;
          --install-dir|-i)
            shift && declare -g script_dir="$1"
            ;;
          --mount-dir|-m)
            shift && declare -g mount_dir="$1"
            ;;
          --temp-dir|-t)
            shift && declare -g temp_dir="$1"
            ;;
          --service-dir)
            shift && declare -g service_dir="$1"
            ;;
          --on-calendar)
            shift && declare -g on_calendar="$1"
            ;;
          --version|-v)
            echo "Version: $version"
            exit 0
            ;;
          --debug)
            echo "Debugging on"
            debug="true"
            ;;
          --help|-h)
            print_help_and_exit 0
            ;;
          --uninstall)
            uninstall="true"
            ;;
          --)
            shift
            break
            ;;
        esac
        shift
      done
    else
      err "Incorrect option(s) provided"
      print_help_and_exit 1
    fi
  }


  err() { echo "Error: $*" >&2; }
  debug() { [[ $debug == "true" ]] && echo "debug: $*"; }


  # Happily check for a command and install its package
  check_and_install() {
    debug "Running: ${FUNCNAME[0]}" "$1"
    if ! command -v "$1" > /dev/null 2>&1; then
      echo "Installing $1"
      [[ -f /etc/os-release ]] && source /etc/os-release
      if [[ "${NAME,,}" =~ (fedora|centos) ]]; then
        debug "sudo dnf install -y $1"
        if ! sudo dnf install -y "$1"; then
          err "Could not install $1, exiting"
          exit 1
        fi
      elif [[ "${NAME,,}" =~ (debian|ubuntu) ]]; then
        debug "sudo apt install -y $1"
        if ! sudo apt install -y "$1"; then
          err "Could not install $1, exiting"
          exit 1
        fi
      else
        err "$1 must be installed"
        exit 1
      fi
    fi
    return $?
  }


  # Happily make directories
  mk_dir() {
    debug "Running: ${FUNCNAME[0]}" "$@"
    local DIR
    for DIR in "$@"; do
      if [[ ! -d "$DIR" ]]; then
        debug "mkdir -p $DIR"
        if ! mkdir -p "$DIR"; then
          debug "sudo mkdir -p $DIR"
          if ! sudo mkdir -p "$DIR"; then
            err "sudo mkdir $DIR failed, exiting"
            exit 1
          fi
        fi
      fi
    done
  }


  # Happily chown directories as $user|$group
  chown_dir() {
    debug "Running: ${FUNCNAME[0]}" "$@"
    local DIR
    local user="$1"
    local group="$2"
    shift 2
    for DIR in "$@"; do
      debug "chown $user:$group -R $DIR"
      if ! chown "$user":"$group" -R "$DIR"; then
        debug "sudo chown $user:$group -R $DIR"
        if ! sudo chown "$user":"$group" -R "$DIR"; then
          err "sudo chown on $DIR failed, exiting"
          exit 1
        fi
      fi
    done
  }


  # Happily make files executable
  make_exec() {
    debug "Running: ${FUNCNAME[0]}" "$@"
    local FILE
    for FILE in "$@"; do
      debug "chmod a+x $FILE"
      if ! chmod a+x "$FILE"; then
        debug "sudo chmod a+x $FILE"
        if ! sudo chmod a+x "$FILE"; then
          err "sudo chmod on $FILE failed, exiting"
          exit 1
        fi
      fi
    done
  }     


  # Happily copy files
  cp_file() {
    debug "Running: ${FUNCNAME[0]}" "$@"
    if [[ ! -f "$1" ]]; then
      err "$1 is missing"
      exit 1
    fi

    [[ -e "$2" ]] && rm_file_dir "$2"

    if ! cp -af "$1" "$2"; then
      err "failed, retrying with sudo"
      debug "sudo cp -f $1 $2"
      if ! sudo cp -af "$1" "$2"; then
        err "Copying script failed, exiting"
        exit 1
      fi
    fi
  }


  # Happily remove a directory/file
  rm_file_dir() {
    debug "Running: ${FUNCNAME[0]}" "$@"
    local OBJ
    for OBJ in "$@"; do
      if [[ -e "$OBJ" ]]; then
        debug "rm -rf $OBJ"
        if ! rm -rf "$OBJ"; then
          err "failed, retrying with sudo"
          debug "sudo rm -rf $OBJ"
          if ! sudo rm -rf "$OBJ"; then
            err "Could not remove $OBJ"
            exit 1
          fi
        fi
      fi
    done
  }


  # Use sed to find ($1) and replace ($2) a string in a file ($3)
  f_and_r() {
    debug "Running: ${FUNCNAME[0]}" "$@"
    debug "s#$1#$2#" "$3"
    if ! sed -i "s#$1#$2#g" "$3"; then
      exit 1
    fi
  }


  _uninstall() {
    if [[ -v name ]]; then
      # Disable timer
      debug "systemctl --user disable--now $name.timer"
      systemctl --user disable --now "$name.timer"
      # Remove service files
      debug "rm_file_dir $service_dir/$name.timer $service_dir/$name.service"
      rm_file_dir "$service_dir/$name.timer" "$service_dir/$name.service"
      # Remove install script
      debug "rm_file_dir $script_dir/$name.sh"
      rm_file_dir "$script_dir/$name.sh"
      # unmount drive
      mountpoint -q -- "$mount_dir" && \
        debug "fusermount -u $mount_dir" && \
        fusermount -u "$mount_dir"
      return 0
    else
      err "\$name must be set to uninstall"
      return 1
    fi
  }


  main() {

    debug "Running: ${FUNCNAME[0]}" "$@"

    # Parse input
    parse_input "$@"
    # Uninstall
    [[ "$uninstall" == "true" ]] && _uninstall
    # Install curlftps
    check_and_install "curlftpfs"
    # Disable existing timer
    debug "systemctl --user disable --now $name.timer"
    systemctl --user disable --now "$name.timer" &> /dev/null
    # Unmount existing ftp share
    mountpoint -q -- "$mount_dir" && \
      debug "fusermount -u $mount_dir" && \
      fusermount -u "$mount_dir"
    # Create directories
    mk_dir "$source_dir" "$mount_dir" "$service_dir" "$script_dir"
    chown_dir "$user" "$group" "$source_dir" "$mount_dir" "$service_dir" "$script_dir"
    # Copy script file
    cp_file "original.sh" "$script_dir/$name.sh"
    make_exec "$script_dir/$name.sh"
    f_and_r "{{mount_dir}}" "$mount_dir" "$script_dir/$name.sh"
    f_and_r "{{source_dir}}" "$source_dir" "$script_dir/$name.sh"
    f_and_r "{{ftp_share}}" "$ftp_share" "$script_dir/$name.sh"
    f_and_r "{{user_id}}" "$user_id" "$script_dir/$name.sh"
    f_and_r "{{group_id}}" "$group_id" "$script_dir/$name.sh"
    f_and_r "{{temp_dir}}" "$temp_dir" "$script_dir/$name.sh"
    # Copy service file
    cp_file "original.service" "$service_dir/$name.service"
    f_and_r "{{path_to_script}}" "$script_dir/$name.sh" "$service_dir/$name.service"
    f_and_r "{{description}}" "$script_dir/$name.sh" "$service_dir/$name.service"
    # Copy timer file
    cp_file "original.timer" "$service_dir/$name.timer"
    f_and_r "{{on_calendar}}" "$on_calendar" "$service_dir/$name.timer"
    f_and_r "{{description}}" "$description" "$service_dir/$name.timer"
    # Run service and enable timer if successful
    debug "systemctl --user daemon-reload"
    systemctl --user daemon-reload
    debug "systemctl --user start $name.service"
    if systemctl --user start "$name.service"; then
      debug "systemctl --user enable --now $name.timer"
      systemctl --user enable --now "$name.timer"
    else
      err "systemctl --user start $name.service failed"
      exit 1
    fi
  }
}


# Allow this file to be executed directly if not being sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    rsync-ftp-timer
    main "$@"
    exit $?
fi
