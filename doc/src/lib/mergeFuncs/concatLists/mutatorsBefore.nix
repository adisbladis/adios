{
  "/foo" = [ pkgs.hello ];
  "/bar" = [
    pkgs.git
    pkgs.cowsay
  ];
}
