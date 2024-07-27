{ config
, ...
}:

{
  imports = [
    ./v4l2loopback
    ./services
    ./desktops
    ./hardware
    ./fonts
    ./programs
  ];

  config = {
    environment.variables = {
      HOST = config.networking.hostName;
    };
  };
}
