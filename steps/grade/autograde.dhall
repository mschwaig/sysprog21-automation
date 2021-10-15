\(manual: Text) -> \(auto: { warnings : Natural }) ->
manual ++ ''
build finished with warnings                   (max.  -15.00): -${
  let min = ./min.dhall
  let div = ./quotient.dhall
  in Natural/show (min (div (auto.warnings + 1) 2).q 15)
  }
''
