echo "hk1box: chainload mainline u-boot from SD/USB (u-boot.ext)"
if fatload mmc 0 0x1000000 u-boot.ext; then go 0x1000000; fi;
for usbdev in 0 1 2 3; do if fatload usb ${usbdev} 0x1000000 u-boot.ext; then go 0x1000000; fi; done;
