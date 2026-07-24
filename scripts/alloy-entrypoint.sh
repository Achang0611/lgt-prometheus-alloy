#!/bin/sh
# Build htpasswd from OTLP_TENANTS and start Alloy.
# OTLP_TENANTS format: tenant:password,tenant2:password2
# Tenant id becomes Basic Auth username and forced resource attribute "tenant".
set -eu

HTPASSWD_FILE="${OTLP_HTPASSWD_FILE:-/tmp/otlp.htpasswd}"

if [ -z "${OTLP_TENANTS:-}" ]; then
  echo "error: OTLP_TENANTS is required (e.g. acme:secret1,beta:secret2)" >&2
  exit 1
fi

: >"${HTPASSWD_FILE}"
count=0

# Portable split on commas without requiring bash arrays
rest="${OTLP_TENANTS}"
while [ -n "${rest}" ]; do
  case "${rest}" in
    *,*)
      pair="${rest%%,*}"
      rest="${rest#*,}"
      ;;
    *)
      pair="${rest}"
      rest=""
      ;;
  esac

  # trim leading/trailing whitespace
  pair="$(printf '%s' "${pair}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [ -z "${pair}" ] && continue

  case "${pair}" in
    *:*)
      tenant="${pair%%:*}"
      password="${pair#*:}"
      ;;
    *)
      echo "error: invalid OTLP_TENANTS entry (want tenant:password): ${pair}" >&2
      exit 1
      ;;
  esac

  tenant="$(printf '%s' "${tenant}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [ -z "${tenant}" ] || [ -z "${password}" ]; then
    echo "error: empty tenant or password in: ${pair}" >&2
    exit 1
  fi

  case "${tenant}" in
    *[!a-zA-Z0-9._-]* | "" )
      echo "error: invalid tenant id '${tenant}' (use [a-zA-Z0-9._-]+)" >&2
      exit 1
      ;;
  esac

  hash="$(openssl passwd -apr1 "${password}")"
  printf '%s:%s\n' "${tenant}" "${hash}" >>"${HTPASSWD_FILE}"
  count=$((count + 1))
done

if [ "${count}" -lt 1 ]; then
  echo "error: OTLP_TENANTS produced no tenants" >&2
  exit 1
fi

export OTLP_HTPASSWD_FILE="${HTPASSWD_FILE}"
echo "alloy-entrypoint: wrote ${count} tenant(s) to ${HTPASSWD_FILE}"

exec alloy run /etc/alloy/config.alloy \
  --storage.path=/var/lib/alloy/data \
  --server.http.listen-addr=0.0.0.0:12345 \
  --stability.level=generally-available
