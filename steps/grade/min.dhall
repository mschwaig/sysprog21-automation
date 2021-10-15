--| `min a b` returns the smaller of `a` or `b`
let lessThanEqual = ./lessThanEqual.dhall

let min
    : Natural → Natural → Natural
    = λ(a : Natural) → λ(b : Natural) → if lessThanEqual a b then a else b

let example0 = assert : min 1 2 ≡ 1

let example1 = assert : min 2 1 ≡ 1

let property0 = λ(n : Natural) → assert : min n n ≡ n

in  min
