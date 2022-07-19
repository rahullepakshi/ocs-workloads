KERNEL_TAR_URL="https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.280.tar.gz"
KERNEL_VERSION=`echo $KERNEL_TAR_URL | cut -d '/' -f8 | sed 's/.tar.gz$//'`
MOUNT=/mnt/test/
MASTER_COPY=$KERNEL_VERSION".tar.gz"
KERNEL_DIRECTORY=$KERNEL_VERSION
MASTER_CHECKSUM_FILE="$MOUNT/kernel_hash"
# Allow only upto 90% full disk space
DISK_SPACE_FULL_THRESHOLD=90
# During make free space, don't delete below 50% usage
FREE_SPACE_THRESHOLD=50

get_disk_usage()
{
    usage=`df $MOUNT --output=pcent | sed -n 2p | cut -d "%" -f1`
    echo $usage
}


# Auto cleanup of directories in case if we don't enough space
# We will bring down the space usage to 50% and stop deletion
# so that if failover occurs at the point after deletion but before
# beginning directory creation we will still have some data
make_free_space()
{
    testdir=`ls -d "$KERNEL_VERSION"_[0-9]* | sed -n 1p`
    rm -rf $testdir
    cur_usage=$(get_disk_usage)
    if [ $cur_usage -gt $FREE_SPACE_THRESHOLD ]; then
        make_free_space
    fi
}

# block if there is no diskspace
block_if_no_space_left()
{
    usage=$(get_disk_usage)
    if [ $usage -gt $DISK_SPACE_FULL_THRESHOLD ]; then
        echo "Disk usage greater than "$DISK_SPACE_FULL_THRESHOLD"%, Can't continue IO"
	sleep 10
	make_free_space
    fi
}

if [ -f "$MOUNT""/""$MASTER_COPY" ]; then
    echo "Master copy tar already exists"
else
    echo "Downloading kernel tar"
    wget $KERNEL_TAR_URL -O $MOUNT/$MASTER_COPY
    if [ $? -eq 0 ];
    then
        echo "Kernel tar ball downloaded successfully"
    else
        echo "Failed to download kernel"
        exit 1
    fi
fi

if [ -f "$MOUNT""/""$MASTER_COPY" ]; then
    if [ -d "$MOUNT""/""$KERNEL_DIRECTORY"_original ]; then
        echo "Reference Kernel dir already exists"
    else
        # If we have broken linux-<version> dir, lets clean it up
        if [ -d "$MOUNT""/""$KERNEL_DIRECTORY" ]; then
            rm -rf $MOUNT/$KERNEL_DIRECTORY
        fi
        cd $MOUNT
        tar xfz $MASTER_COPY
        if [ $? -ne 0 ];
        then
            echo "Failed to untar reference kernel"
            exit 1
        fi
        arequal-checksum $MOUNT/$KERNEL_DIRECTORY>$MASTER_CHECKSUM_FILE
        mv $MOUNT/$KERNEL_DIRECTORY $MOUNT/$KERNEL_DIRECTORY"_original"
    fi
fi

# From here keep a loop of untaring and renaming the kernel dirs
while true
do
    block_if_no_space_left
    # There could be half untared linx dir
    # may be due to failover , so we need to cleanup
    if [ -d $KERNEL_DIRECTORY ]; then
        rm -rf $KERNEL_DIRECTORY
    fi
    cd $MOUNT
    tar xfz $MASTER_COPY
    if [ $? -ne 0 ];
    then
        echo "Failed to untar kernel"
        exit 1
    fi
    mv $MOUNT/$KERNEL_DIRECTORY $MOUNT/$KERNEL_DIRECTORY"_`date +%s`"
done
