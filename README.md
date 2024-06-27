# dotfiles
NixOS dotfiles directory: my experimental descent into madness

## Next step: get a status bar!!!

### DEPS:
  - playerctl: hm module, use playerctld
  - rofi in general
    - rofi-wayland-unwrapped: hm module
    - rofi-bluetooth
    - investigate ML4W dope ass Rofi customization???
  - waybar: hm module
  - python3
  - swaylock/hyprlock
  - hyprpapr, colour dependent on bg too
  - spicetify: GTK themed spotify
  - betterdiscord?

### TODO: 
  - [ ] rice out rofi
  - [ ] get swaync
  - [x] swaylock/hyprlock
    - [ ] rice it out
  - [x] ~hyprpapr~ swww
    - [x] set layer to black: done through hyprland disabling default layer
    - [ ] colour dependent on bg too
    - [ ] contribute: cache the dims/scale of the last img too
  - [x] hypridle
    - [ ] post-wake fixes: set background
    - [ ] kanshi on wake
  - [ ] improve the Hyprland keybindings
  - [ ] convert to pulseaudio to pipewire/wireplumber, use wpctl?
  - [x] any GUI for pipewire? qpwgraph, pavucontrol
    - pavucontrol!
  - [x] create overlay for my own packages
    - waybar-balcony
    - ~rofi-bluetooth-balcony~
    - scythe
    - [ ] run-cwd(-sway)
  - [ ] implement: run-cwd-hyprland
