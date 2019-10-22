#!/bin/bash
#
# Script Name...: objectstorage-simple-backup.sh
#
# Author........: Daniel Armbrust - daniel.armbrust@oracle.com
# Date..........: 10/20/2019
#
# Description...: The following script makes a backup files from /var/www and
#  MySQL Dumps. After that, those files will be transfered to OCI Object Storage.
#
#

#
# Globals
#

BACKUP_ROOT_DIR="/home/backup"
OCI_CLI_ROOT_DIR="/opt/bin"
CURRENT_DATETS="$(date +%d%m%y-%s)"
BUCKET_NAME="backup"
DB_USER="dbuser"
DB_PASSWD="XXXXXXXXXX"

#
# Functions
#

log_msg() {
  #
  # Makes entries in the system log through logger binary.
  #
  local level="$1"
  local msg="$2"

  logger -i -s -t "BACKUP" -p "user.$level" "$msg"
}


os_upload() {
  #
  # Upload files to Object Storage
  #
  local src_file="$1"

  $OCI_CLI_ROOT_DIR/oci os object put --bucket-name "$BUCKET_NAME" --file "$src_file"

  if [ $? -eq 0 ]; then
    log_msg "info" "File \"$src_file\" uploaded successful to Object Storage."
  else
    log_msg "err" "ERROR to upload the file \"$src_file\" to Object Storage."
  fi
}


db_bkp() {
  #
  # Database backup
  #
  local tmp_dir="$1"

  local db_list=('db01' 'db02' 'db03' 'db04' 'db05')

  local db_name=""
  local dump_filename=""

  local i=0

  while [ $i -lt ${#db_list[*]} ]; do

    db_name="${db_list[$i]}"
    dump_filename="$tmp_dir/$db_name-dump-$CURRENT_DATETS.gz"

    log_msg "info" "DUMPing database \"$db_name\" -> \"$dump_filename\" ..."

    mysqldump -u "$DB_USER" -p"$DB_PASSWD" --single-transaction --quick \
      --lock-tables=false --triggers --routines --events \
      "$db_name" | gzip -9 >"$dump_filename"

    if [ $? -eq 0 ]; then
      os_upload "$dump_filename"
    else
      log_msg "err" "ERROR to create the DUMP file \"$dump_filename\"."
    fi

    test -f "$dump_filename" && rm -f "$dump_filename"

    let i+=1
  done
}


site_bkp() {
  #
  # Backup /var/www/html/* files
  #
  local tmp_dir="$1"

  local site_dir="/var/www/html"
  local tar_filename="$tmp_dir/html-backup-$CURRENT_DATETS.tar.gz"

  log_msg "info" "TARing \"$site_dir\" -> \"$tar_filename\" ..."

  tar --acls -czpf "$tar_filename" --absolute-names "$site_dir"

  if [ $? -eq 0 ]; then
    os_upload "$tar_filename"
  else
    log_msg "err" "ERROR to create the TAR file \"$tar_filename\"."
  fi

  test -f "$tar_filename" && rm -f "$tar_filename"
}

check_bucket() {
  #
  # Check if the bucket exists.
  #

  $OCI_CLI_ROOT_DIR/oci os bucket get --bucket-name "$BUCKET_NAME" &>/dev/null

  if [ $? -ne 0 ]; then
    log_msg "err" "The Bucket \"$BUCKET_NAME\" does not exists! Exiting ..."
    exit 1
  fi
}

start_bkp() {
  #
  # Start backup procedures.
  #

  if [ -d "$BACKUP_ROOT_DIR" ]; then

    tmp_dir=$(mktemp -d -p "$BACKUP_ROOT_DIR" 2>/dev/null)

    if [ -d "$tmp_dir" ]; then
      check_bucket
      site_bkp "$tmp_dir"
      db_bkp "$tmp_dir"
      rmdir "$tmp_dir"
    else
      log_msg "err" "Cannot create BACKUP temp directory \"$tmp_dir\"."
      log_msg "err" "Backup procedures terminated with ERROR!"
      exit 1
    fi

  else
    log_msg "err" "The BACKUP root directory \"$BACKUP_ROOT_DIR\" does not exists!"
    log_msg "err" "Backup procedures terminated with ERROR!"
    exit 1
  fi
}

start_bkp
log_msg "info" "Backup procedures completed."
exit 0
