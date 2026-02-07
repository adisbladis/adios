{ korora }:

let
  inherit (builtins) isString;
  inherit (korora)
    any
    attrs
    attrsOf
    function
    listOf
    never
    option
    optionalAttr
    string
    struct
    type
    typedef
    typedef'
    union
    ;

  neverAttr = optionalAttr never;

  typesT = attrsOf modules.typedef;

  modules = {
    typedef =
      typedef' "typedef"
        (union [
          function
          type
          typesT
        ]).verify;

    option =
      (struct "option" {
        inherit type;
        description = optionalAttr string;
        default = optionalAttr any;
        defaultFunc = optionalAttr function;
        mutators = optionalAttr (listOf string);
        mutatorType = optionalAttr type;
        mergeFunc = optionalAttr function;
        example = optionalAttr any;
      }).override
        {
          verify =
            option:
            if option ? default && option ? defaultFunc then
              "'default' & 'defaultFunc' are mutually exclusive"
            else
              null;
        };

    mutatedOption =
      (struct "optionBeingMutated" {
        mutators = listOf string;
        inherit type;
        mutatorType = type;
        mergeFunc = function;
        description = optionalAttr string;
        example = optionalAttr any;
      }).override
        {
          verify =
            option:
            if option ? default then
              "options that set 'mutators' shouldn't provide a 'default'"
            else if option ? defaultFunc then
              "options that set 'mutators' shouldn't provide a 'defaultFunc'"
            else
              null;
        };

    subOptions = struct "subOptions" {
      inherit (modules) options;
      description = optionalAttr string;
      # Make fields used for normal options non-permitted
      type = neverAttr;
      default = neverAttr;
      defaultFunc = neverAttr;
    };

    options = attrsOf (union [
      modules.option
      modules.subOptions
    ]);

    input = option (
      attrsOf (
        struct "input" {
          # Note: The lack of a type for an input means no type checking done.
          type = optionalAttr type;
          # TODO: Narrow permitted chars
          path = typedef "pathstring" isString;
        }
      )
    );

    inputs = attrsOf modules.input;
    mutation = attrsOf function;
    lib = attrs;
  };

in
korora // { inherit modules; }
