mergeFunc:
{ mutators }:
let
  inherit (builtins)
    genList
    length
    elemAt
    listToAttrs
    stringLength
    attrValues
    sort
    ;

  sorted = sort (a: b: a.priority < b.priority) (attrValues mutators);
  numMutators = length sorted;
  maxKeyLength = stringLength (toString (numMutators - 1));

  # We need to pad each key with zeros, so when the next functoin calls
  # attrValues, the lexicographical ordering gives us our desired result. This
  # means in a list of length 11, 5 should become 05.
  #
  # Rather than computing these leading zeros on every single iteration, we can
  # precompute them, and do a lookup. This means we only have to call replicate
  # log_10(n) times!
  #
  # We also purposefully give this table an off-by-one error and make it
  # 1-indexed. This prevents us from having to subtract 1 on every single
  # iteration.
  zeroesLookupTable = genList (
    index: if index == maxKeyLength then "" else "0" + elemAt zeroesLookupTable (index + 1)
  ) (maxKeyLength + 1);
in
mergeFunc {
  mutators = listToAttrs (
    genList (
      index:
      let
        str = toString index;
      in
      {
        name = elemAt zeroesLookupTable (stringLength str) + str;
        value = (elemAt sorted index).value;
      }
    ) numMutators
  );
}
