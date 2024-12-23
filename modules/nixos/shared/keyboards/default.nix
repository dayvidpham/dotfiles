{ config
, pkgs
, lib ? pkgs.lib
, ...
}:

{
  # to allow flashing of QMK Via-compatible keyboards
  # for the Iris CE Rev. 1
  services.udev.extraRules = ''
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="cb10", ATTRS{idProduct}=="1556", MODE="0660", GROUP="users", TAG+="uaccess", TAG+="udev-acl"
  '';
}
