#!/bin/bash

if [ "$(id -u)" != '0' ]; then
    echo "Run this script as root!\n"
    exit 1
fi

wdir="/usr/local/cranberry"
bind_dir="/opt/google/containers/android/rootfs/android-data/data/adb/su"
android_rootfs="/opt/google/containers/android/rootfs"
device_arch=$(uname -m)
# abiVer=$(cat /opt/google/containers/android/rootfs/root/system/build.prop | grep "ro.build.version.sdk=")
android_su_dl="https://download.chainfire.eu/1220/SuperSU/SR5-SuperSU-v2.82-SR5-20171001224502.zip?retrieve_file=1"
busybox_arm_dl="https://busybox.net/downloads/binaries/1.28.1-defconfig-multiarch/busybox-armv7l"
busybox_x86_dl="https://busybox.net/downloads/binaries/1.28.1-defconfig-multiarch/busybox-i686"

# Clean up from a previous attempt if applicable

touch /etc/cranberry-test
sleep 0.5

if [ ! -e "/etc/cranberry-test" ]; then
    echo "Your rootfs doesn't seem to be writable. Make sure you run\nsudo /usr/share/vboot/bin/make_dev_ssd.sh --remove_rootfs_verification --partitions 2\nbefore you run this script.\n"
    exit 1
fi

rm /etc/cranberry-test

if [ -L "/opt/google/containers/android/system.raw.img" ]; then
    echo "System Image already replaced with symlink?\n"
    rm /opt/google/containers/android/system.raw.img
    if [ -e "/opt/google/containers/android/system.original.img" ]; then
        echo "Has CrAnberry already been run? No problem. I can correct it.\n"
        rm /opt/google/containers/android/system.raw.img
        mv /opt/google/containers/android/system.original.img /opt/google/containers/android/system.raw.img

    else
        echo "There's a symlink in place for the android image, but no original image to work with?\nGet a copy of your device's system.raw.img and put it in \"/opt/google/containers/android/\"\n"
        rm /opt/google/containers/android/system.raw.img
        exit 1
    fi
    
elif [ -e "/opt/google/containers/android/system.original.img" ]; then
    if [ ! -e "$android_rootfs/android-data/data/app" ]; then
        echo "Android Container not running after what seems like a previous attempt.\nReboot before running this script again.\n"
        mv /opt/google/containers/android/system.original.img /opt/google/containers/android/system.raw.img
        exit 1
    else 
        mv /opt/google/containers/android/system.original.img /opt/google/containers/android/system.raw.img
    fi
    
elif [ ! -e "/opt/google/containers/android/system.raw.img" ]; then
    echo "No android system image present in /opt/google/containers/android/"
    exit 1
        
elif [ ! -e "$android_rootfs/android-data/data/app" ]; then
    echo "Android subsystem does not appear to be active."
    exit 1;
    
fi

if [ -e $wdir ]; then
    umount $wdir/original
    umount $wdir/new
    rm -rf $wdir
fi

rm -rf $bind_dir

# Create work directory and image

if [ ! -e "/usr/local/bin" ]; then
mkdir /usr/local/bin
fi

if [ ! -e "/usr/local/bak" ]; then
mkdir /usr/local/bak
fi

mkdir $wdir
mkdir $wdir/supersu
mkdir -p $bind_dir/su
mkdir $bind_dir/bin
mkdir $bind_dir/lib
mkdir $bind_dir/ext
dd if=/dev/zero of=$wdir/cranberry.img bs=1 count=0 seek=2G
mkdir $wdir/original
mkdir $wdir/new
mkfs.ext4 $wdir/cranberry.img
mount -o loop,rw,sync $wdir/cranberry.img $wdir/new

# Move the existing image ...

mv /opt/google/containers/android/system.raw.img /opt/google/containers/android/system.original.img

# ... and mount it

mount -o loop,ro /opt/google/containers/android/system.original.img $wdir/original

# Set the SELinux policy to permissive

setenforce 0
secon=$(getenforce)
if [ "$secon"="Permissive" ]; then
    echo "SELinux set to Permissive.\n"
else
    echo "SELinux failed to change to Permissive.\n"
    exit 1
fi

# Attempt to copy the files into the new image

echo "Copying files into new android image\nErrors about acct, dev, or oem are normal\n"

cp -ar $wdir/original/* $wdir/new/
mkdir $wdir/new/acct
mkdir $wdir/new/dev
mkdir -p $wdir/new/oem/etc
sync

# Unmount original image

umount $wdir/original

# Copying AROC here:

if [ "$device_arch"="armv7l" ] || [ "$device_arch"="armv8l" ] || [ "$device_arch"="aarch64" ]; then
    boxSizeCheck=$(stat -c %s /usr/local/bin/busybox)
    if [ "$boxSizeCheck" != 1079156 ]; then
        curl $busybox_arm_dl -o /usr/local/bin/busybox
        boxSizeCheck=$(stat -c %s /usr/local/bin/busybox)
        if [ "$boxSizeCheck" != 1079156 ]; then
            echo "Busybox failed to download. Retrying.\n"
            rm /usr/local/bin/busybox
            curl $busybox_arm_dl -o /usr/local/bin/busybox
            boxSizeCheck=$(stat -c %s /usr/local/bin/busybox)
            if [ "$boxSizeCheck" != 1079156 ]; then
                echo "Failed to download again. Check your internet.\n"
                rm /usr/local/bin/busybox
                cd /
                exit 1
            fi
        fi
    fi
    
chmod +x /usr/local/bin/busybox
    
elif [ "$device_arch"="x86" ] || [ "$device_arch"="x86_64" ]; then
    boxSizeCheck=$(stat -c %s /usr/local/bin/busybox)
    if [ "$boxSizeCheck" != 935060 ]; then
        curl $busybox_x86_dl -o /usr/local/bin/busybox
        boxSizeCheck=$(stat -c %s /usr/local/bin/busybox)
        if [ "$boxSizeCheck" != 935060 ]; then
            echo "Busybox failed to download. Retrying.\n"
            rm /usr/local/bin/busybox
            curl $busybox_x86_dl -o /usr/local/bin/busybox
            boxSizeCheck=$(stat -c %s /usr/local/bin/busybox)
            if [ "$boxSizeCheck" != 935060 ]; then
                echo "Failed to download again. Check your internet.\n"
                rm /usr/local/bin/busybox
                cd /
                exit 1
            fi
        fi
    fi
     
chmod +x /usr/local/bin/busybox
     
else
    echo "Unrecognized device arch $device_arch\n"
    exit 1
fi

if [ -e $wdir/supersu.zip ]; then
    rm $wdir/supersu.zip
fi

zipSizeCheck=$(stat -c %s $wdir/supersu/supersu.zip)
if [ "$zipSizeCheck" != 6882992 ]; then
    curl $android_su_dl -o $wdir/supersu/supersu.zip
    zipSizeCheck=$(stat -c %s $wdir/supersu/supersu.zip)
    if [ "$zipSizeCheck" != 6882992 ]; then
        echo "File did not download correctly! Retrying.\n"
        rm $wdir/supersu/supersu.zip
        curl $android_su_dl -o $wdir/supersu/supersu.zip
        zipSizeCheck=$(stat -c %s $wdir/supersu/supersu.zip)
        if [ "$zipSizeCheck" != 6882992 ]; then
            echo "File failed to download again. Trying once more.\n"
            rm $wdir/supersu/supersu.zip
            curl $android_su_dl -o $wdir/supersu/supersu.zip
            zipSizeCheck=$(stat -c %s $wdir/supersu/supersu.zip)
            if [ "$zipSizeCheck" != 6882992 ]; then
                echo "File failed to download 3 times. Check your internet.\n"
                exit 1
            fi
        fi
    fi
echo "Unzipping SuperSU...\n"
cd $wdir/supersu/
/usr/local/bin/busybox unzip $wdir/supersu/supersu.zip
cd $wdir
fi

sleep 2

# Now we take the necessary files and set the appropriate permissions...

echo "Installing SU.\n"

if [ "$device_arch"="armv7l" ] || [ "$device_arch"="armv8l" ] || [ "$device_arch"="aarch64" ]; then
    cp $wdir/supersu/armv7/su $wdir/new/system/xbin/su
    cp $wdir/supersu/armv7/su $wdir/new/system/xbin/daemonsu
    cp $wdir/supersu/armv7/su $wdir/new/system/xbin/sugote
    cp $wdir/supersu/armv7/supolicy $wdir/new/system/xbin/supolicy
    cp $wdir/supersu/armv7/libsupol.so $wdir/new/system/lib/libsupol.so
    
    chmod 0755 $wdir/new/system/xbin/su
    chmod 0755 $wdir/new/system/xbin/daemonsu
    chmod 0755 $wdir/new/system/xbin/sugote
    chmod 0755 $wdir/new/system/xbin/supolicy
    chmod 0644 $wdir/new/system/lib/libsupol.so
    
    chown 655360 $wdir/new/system/xbin/su
    chown 655360 $wdir/new/system/xbin/daemonsu
    chown 655360 $wdir/new/system/xbin/sugote
    chown 655360 $wdir/new/system/xbin/supolicy
    chown 655360 $wdir/new/system/lib/libsupol.so
    
    chgrp 655360 $wdir/new/system/xbin/su
    chgrp 655360 $wdir/new/system/xbin/daemonsu
    chgrp 655360 $wdir/new/system/xbin/sugote
    chgrp 655360 $wdir/new/system/xbin/supolicy
    chgrp 655360 $wdir/new/system/lib/libsupol.so
    
    chcon u:object_r:system_file:s0 $wdir/new/system/xbin/su
    chcon u:object_r:system_file:s0 $wdir/new/system/xbin/daemonsu
    chcon u:object_r:zygote_exec:s0 $wdir/new/system/xbin/sugote
    chcon u:object_r:system_file:s0 $wdir/new/system/xbin/supolicy
    chcon u:object_r:system_file:s0 $wdir/new/system/lib/libsupol.so

    mkdir $wdir/new/system/bin/.ext
    chmod 0777 $wdir/new/system/bin/.ext
    
    cp $wdir/supersu/armv7/su $wdir/new/system/bin/.ext/.su
    chmod 0755 $wdir/new/system/bin/.ext/.su
    chown 655360 $wdir/new/system/bin/.ext/.su
    chgrp 655360 $wdir/new/system/bin/.ext/.su
    chcon u:object_r:system_file:s0 $wdir/new/system/bin/.ext/.su
    
    # and copy temp files to patch SELinux
    cp $wdir/supersu/armv7/su $bind_dir/bin/su
    cp $wdir/supersu/armv7/su $bind_dir/bin/daemonsu
    cp $wdir/supersu/armv7/su $bind_dir/bin/sugote
    
    chmod 0755 $bind_dir/bin/su
    chmod 0755 $bind_dir/bin/daemonsu
    chmod 0755 $bind_dir/bin/sugote
    
    chown 655360 $bind_dir/bin/su
    chown 655360 $bind_dir/bin/daemonsu
    chown 655360 $bind_dir/bin/sugote
    
    chgrp 655360 $bind_dir/bin/su
    chgrp 655360 $bind_dir/bin/daemonsu
    chgrp 655360 $bind_dir/bin/sugote
    
    chcon u:object_r:system_file:s0 $bind_dir/bin/su
    chcon u:object_r:system_file:s0 $bind_dir/bin/daemonsu
    chcon u:object_r:zygote_exec:s0 $bind_dir/bin/sugote
    
    cp $wdir/supersu/armv7/supolicy $bind_dir/bin/supolicy
    chmod 0755 $bind_dir/bin/supolicy
    chown 655360 $bind_dir/bin/supolicy
    chgrp 655360 $bind_dir/bin/supolicy
    chcon u:object_r:system_file:s0 $bind_dir/bin/supolicy
    
    cp $wdir/supersu/armv7/libsupol.so $bind_dir/lib/libsupol.so
    chmod 0644 $bind_dir/lib/libsupol.so
    chown 655360 $bind_dir/lib/libsupol.so
    chgrp 655360 $bind_dir/lib/libsupol.so
    chcon u:object_r:system_file:s0 $bind_dir/lib/libsupol.so
    

elif [ "$device_arch"="x86" ] || [ "$device_arch"="x86_64" ]; then
    cp $wdir/supersu/x86/su.pie $wdir/new/system/xbin/su
    cp $wdir/supersu/x86/su.pie $wdir/new/system/xbin/daemonsu
    cp $wdir/supersu/x86/su.pie $wdir/new/system/xbin/sugote
    cp $wdir/supersu/x86/supolicy $wdir/new/system/xbin/supolicy
    cp $wdir/supersu/x86/libsupol.so $wdir/new/system/lib/libsupol.so
    
    chmod 0755 $wdir/new/system/xbin/su
    chmod 0755 $wdir/new/system/xbin/daemonsu
    chmod 0755 $wdir/new/system/xbin/sugote
    chmod 0755 $wdir/new/system/xbin/supolicy
    chmod 0644 $wdir/new/system/lib/libsupol.so
    
    chown 655360 $wdir/new/system/xbin/su
    chown 655360 $wdir/new/system/xbin/daemonsu
    chown 655360 $wdir/new/system/xbin/sugote
    chown 655360 $wdir/new/system/xbin/supolicy
    chown 655360 $wdir/new/system/lib/libsupol.so
    
    chgrp 655360 $wdir/new/system/xbin/su
    chgrp 655360 $wdir/new/system/xbin/daemonsu
    chgrp 655360 $wdir/new/system/xbin/sugote
    chgrp 655360 $wdir/new/system/xbin/supolicy
    chgrp 655360 $wdir/new/system/lib/libsupol.so
    
    chcon u:object_r:system_file:s0 $wdir/new/system/xbin/su
    chcon u:object_r:system_file:s0 $wdir/new/system/xbin/daemonsu
    chcon u:object_r:zygote_exec:s0 $wdir/new/system/xbin/sugote
    chcon u:object_r:system_file:s0 $wdir/new/system/xbin/supolicy
    chcon u:object_r:system_file:s0 $wdir/new/system/lib/libsupol.so

    mkdir $wdir/new/system/bin/.ext
    chmod 0777 $wdir/new/system/bin/.ext
    
    cp $wdir/supersu/x86/su.pie $wdir/new/system/bin/.ext/.su
    chmod 0755 $wdir/new/system/bin/.ext/.su
    chown 655360 $wdir/new/system/bin/.ext/.su
    chgrp 655360 $wdir/new/system/bin/.ext/.su
    chcon u:object_r:system_file:s0 $wdir/new/system/bin/.ext/.su
    
    # and copy temp files to patch SELinux
    cp $wdir/supersu/x86/su.pie $bind_dir/bin/su
    cp $wdir/supersu/x86/su.pie $bind_dir/bin/daemonsu
    cp $wdir/supersu/x86/su.pie $bind_dir/bin/sugote
    
    chmod 0755 $bind_dir/bin/su
    chmod 0755 $bind_dir/bin/daemonsu
    chmod 0755 $bind_dir/bin/sugote
    
    chown 655360 $bind_dir/bin/su
    chown 655360 $bind_dir/bin/daemonsu
    chown 655360 $bind_dir/bin/sugote
    
    chgrp 655360 $bind_dir/bin/su
    chgrp 655360 $bind_dir/bin/daemonsu
    chgrp 655360 $bind_dir/bin/sugote
    
    chcon u:object_r:system_file:s0 $bind_dir/bin/su
    chcon u:object_r:system_file:s0 $bind_dir/bin/daemonsu
    chcon u:object_r:zygote_exec:s0 $bind_dir/bin/sugote
    
    cp $wdir/supersu/x86/supolicy $bind_dir/bin/supolicy
    chmod 0755 $bind_dir/bin/supolicy
    chown 655360 $bind_dir/bin/supolicy
    chgrp 655360 $bind_dir/bin/supolicy
    chcon u:object_r:system_file:s0 $bind_dir/bin/supolicy
    
    cp $wdir/supersu/x86/libsupol.so $bind_dir/lib/libsupol.so
    chmod 0644 $bind_dir/lib/libsupol.so
    chown 655360 $bind_dir/lib/libsupol.so
    chgrp 655360 $bind_dir/lib/libsupol.so
    chcon u:object_r:system_file:s0 $bind_dir/lib/libsupol.so

else 
    echo "How did you even get here? Unknown arch!\n"
    exit 1
fi

# Though it's not strictly necessary, we'll also copy in busybox, but no symlinks

cp /usr/local/bin/busybox $wdir/new/system/xbin/busybox
chown 655360 $wdir/new/system/xbin/busybox
chgrp 655360 $wdir/new/system/xbin/busybox
chmod 4755 $wdir/new/system/xbin/busybox

# Patching SELinux breaks things, so we have to be careful.

if [ ! -e /usr/local/bak/policy.30.bak ]; then
    cp /etc/selinux/arc/policy/policy.30 /usr/local/bak/policy.30.bak
fi

if [ ! -e /etc/selinux/arc/policy/policy.30.bak ]; then
    cp /etc/selinux/arc/policy/policy.30 /etc/selinux/arc/policy/policy.30.bak
fi

if [ ! -e /usr/local/bak/android_sepolicy.bak ]; then
    cp $wdir/new/sepolicy /usr/local/bak/android_sepolicy.bak
fi

if [ ! -e /usr/share/arc-setup/config.json.bak ]; then
    cp /usr/share/arc-setup/config.json /usr/share/arc-setup/config.json.bak
fi

### EDITING THE config.json TO MOUNT THE SYSTEM AS RW WILL PERMANENTLY BREAK 9.0 SYSTEM IMAGES. DON'T DO IT. ###
echo "Do NOT edit /usr/share/arc-setup/config.json. Making changes to this file will permanently trash your new image.\nIf you want to make changes to your system, remove the symlink, reboot, and mount it as a loop device using\n\"mount -o loop,rw,sync /usr/local/cranberry/system.rooted.img /usr/local/cranberry/new\"\n"

cp -ar $android_rootfs/root/system/lib/* $bind_dir/lib/
cp -ar $android_rootfs/root/sbin/* $bind_dir/bin/

echo "Patching SELinux. Android apps will stop working until reboot.\n"

cp /etc/selinux/arc/policy/policy.30 /home/chronos/user/Downloads/policy.30

echo "mount -o bind /data/adb/su/bin /sbin" | android-sh
echo "mount -o bind /data/adb/su/lib /system/lib" | android-sh
echo "supolicy --file /var/run/arc/sdcard/default/emulated/0/Download/policy.30 /var/run/arc/sdcard/default/emulated/0/Download/policy.30_new --sdk=28" | android-sh
echo 'chmod 0644 /var/run/arc/sdcard/default/emulated/0/Download/policy.30_new' | android-sh

cp -a /home/chronos/user/Downloads/policy.30_new /etc/selinux/arc/policy/policy.30
cp -a /home/chronos/user/Downloads/policy.30_new $wdir/new/sepolicy

chown 655360 $wdir/new/sepolicy
chgrp 655360 $wdir/new/sepolicy
chcon u:object_r:rootfs:s0 $wdir/new/sepolicy

# and finally, symlink the new rootfs to the right place

umount $wdir/new
mv $wdir/cranberry.img $wdir/system.rooted.img
ln -s /usr/local/cranberry/system.rooted.img /opt/google/containers/android/system.raw.img

echo "Reboot and enjoy!\n"
exit 0