mount_disk()
{
  local fileDisk="$1"
  local filePartition="$2"
  # check if the file partition exists
  df | grep -q "${filePartition}"

  if [ $? -gt 0 ]; then
    # Create Disk partition
    printf "n\np\n1\n\n\nw\n" | fdisk ${fileDisk}
    # Format the disk partition
    mkfs -t ext4 ${filePartition}
    # mount /opt to the partition
    mount ${filePartition}  /opt
    # ghet uuid for filePartition
    local uuid=$(blkid "${filePartition}" | cut -d" " -f2 | tr -d '"')
    # Generate dstab entry and append to /etc/fstab
    local line="${uuid}   /opt   ext4   defaults,nofail   1   2"
    echo $line >> /etc/fstab
  fi
}

mount_disk '/dev/sdc' '/dev/sdc1'
