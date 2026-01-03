{
  "/foo" = {
    nested.a = 1;
    list = [
      1
      2
      3
    ];
  };
  "/bar" = {
    nested.b = 2;
    list = [ 4 ];
  };
  "/baz" = {
    nested.doubleNested.c = 3;
    onlyUsedOnce = 1;
  };
}
