_: let
  javaVersion = 17;
in (_slef: super: {
  maven = super.maven.override {
    jdk = super."jdk${toString javaVersion}";
  };
})
