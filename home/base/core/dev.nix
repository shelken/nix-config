{
  mylib,
  ...
}:
{
  options.shelken.dev.ide = {
    enable = mylib.mkBoolOpt false "Whether or not use to enable.";
  };
  options.shelken.dev.ops = {
    enable = mylib.mkBoolOpt false "Whether or not use to enable.";
  };
  options.shelken.dev.cloud-native = {
    enable = mylib.mkBoolOpt false "Whether or not use to enable.";
  };
}
