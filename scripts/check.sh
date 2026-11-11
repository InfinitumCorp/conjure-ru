#!/bin/bash
# Outside checks for Conjure Russia. Exits non-zero if any check fails.
set -uo pipefail
APP=${1:-https://conjure-ru.infinitumcorporation.ai}
PREVIEW=${2:-https://conjure-ru-preview.infinitumcorporation.ai}
fail=0
check() { # name expected-code url
  local got; got=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 --retry 3 "$3")
  if [ "$got" = "$2" ]; then echo "ok   $1 ($got)"; else echo "FAIL $1: got $got, want $2"; fail=1; fi
}
check "healthz"                   200 "$APP/healthz"
check "home needs sign-in"        303 "$APP/"
check "login page"                200 "$APP/login"
check "API needs a session"       401 "$APP/api/status"
check "http redirects to https"   301 "${APP/https:/http:}/healthz"
check "preview host answers"      400 "$PREVIEW/"
page=$(curl -s --max-time 20 --retry 3 "$APP/login")
for want in "Sign in with Cumulus ID" "Create a Cumulus ID"; do
  if grep -q "$want" <<<"$page"; then echo "ok   login offers \"$want\""; else echo "FAIL login is missing \"$want\""; fail=1; fi
done
exit $fail
