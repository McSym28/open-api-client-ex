# Used by "mix format"
[
  inputs: ["*.{ex,exs}", "{config,lib,test}/**/*.{ex,exs}"],
  import_deps: if(Mix.env() == :test, do: [:phoenix], else: [])
]
