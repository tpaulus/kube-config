parser {
  include    = [ "(_alerts/.*[.]yaml)$" ]
}

ci {
  baseBranch = "main"
}