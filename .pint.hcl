prometheus "Brickyard" {
  uri         = "https://prometheus.auth-ing.k3s.brickyard.whitestar.systems"
  headers     = {
    "CF-Access-Client-Id": "${ENV_PINT_BRICKYARD_CLIENT_ID}",
    "CF-Access-Client-Secret": "${ENV_PINT_BRICKYARD_CLIENT_SECRET}"
  }
}

parser {
  include    = [ "(_alerts/.*)" ]
  baseBranch = "main"
}