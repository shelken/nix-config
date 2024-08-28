_: let
  javaVersion = 17;
in (_slef: super: {
  maven = super.maven.override {
    jdk_headless = super."jdk${toString javaVersion}_headless";
  };
})
