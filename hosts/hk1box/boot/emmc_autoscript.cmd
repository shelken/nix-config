echo "hk1box: chainload mainline u-boot from eMMC (u-boot.emmc)"
if fatload mmc 1 0x1000000 u-boot.emmc; then go 0x1000000; fi;
