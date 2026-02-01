{
  "/foo" = {
    nested.a = "demo";
  };
  "/bar" = {
    nested.b = 2;
  };
  "/baz" = {
    nested.doubleNested.c = null;
    onlyUsedOnce = true;
  };
}
