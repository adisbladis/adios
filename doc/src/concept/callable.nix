{ types, ... }:
{
  name = "callable-module";

  options = {
    foo = {
      type = types.string;
      default = "foo";
    };
  };

  # impl takes the values set for each option. The user can specify their own
  # value for `options.foo`, or just fall back on the default
  impl =
    { options }:
    {
      # Evaluating someValue.bar will typecheck options.foo
      someValue.bar = options.foo;
    };
}
