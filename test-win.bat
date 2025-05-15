@echo off

qemu-system-i386.exe -fda disk_images/mikeos.flp -S -gdb tcp::14200