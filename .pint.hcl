prometheus "Brickyard" {
  uri         = "https://prometheus.ing.k3s.brickyard.whitestar.systems"
}

parser {
  include    = [ "(_alerts/.*)" ]
}

ci {
  baseBranch = "main"
}