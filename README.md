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
    - [ ] contribute: animation getting stuck and only displaying single pixel? needs two calls to `swww img`
  - [x] hypridle
    - [x] post-wake fixes: set background (handled via swww systemd unit)
    - [ ] kanshi on wake
    - [ ] unmute on wake
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
