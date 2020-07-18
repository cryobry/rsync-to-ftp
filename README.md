Usage: 

1. Configure user options in `install.sh`
2. Run `./install.sh` as your normal user
3. Confirm that user services are running and enabled: `systemctl --user status $name.service; systemctl --user status $name.timer`
4. If errors occur, check journal output: `journalctl -r -u $name.service`

Notes:

1. curlftpfs doesn't support file permissions, thus we must only use -r in rsync
2. curlftpfs doesn't support temporary files, thus the intermediate temp file step
3. I mount the share to /media (by design so that my file manager will display it if it is erroneously mounted) but it may be easier for users to mount the ftp share somewhere in $HOME to avoid permissions issues