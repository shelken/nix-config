{
  mylib,
  ...
}:
{
  options.shelken.dev.cloud-native.enable = mylib.mkBoolOpt false "Whether or not use to enable.";

  config.shelken.internal.homeModules = [ ./home.nix ];
}
