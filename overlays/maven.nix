_:
let 
  javaVersion = 17;
in
(slef: super: {
  maven = super.maven.override {
    jdk = super."jdk${toString javaVersion}";
  };
})
