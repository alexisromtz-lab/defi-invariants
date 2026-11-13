#!/bin/sh
# Ejecutor declarado de la capsula `inflacion-de-la-primera-accion`.
# HUELLA-CAPSULA-INFLACION-20261113
#
# Contrato que este script cumple, y que tools/verificar_capsulas_web3.py fija
# sin preguntar:
#
#   correr.sh ataque       -> rc != 0   (el invariante esta roto: la prueba revierte)
#   correr.sh remediacion  -> rc == 0   (el parche lo cierra)
#
# Si `forge` no esta instalado sale 127 a proposito: es la convencion POSIX de
# «no encontrado», y el verificador la lee como NO_MEDIDO. Salir 1 aqui seria
# mentir: diria «ataque exitoso» sin haber ejecutado una sola linea.
#
# HUELLA-CAPSULA-ARTEFACTOS-FUERA-DEL-ARBOL-20261113
# `forge test` escribe `out/` y `cache/` junto a foundry.toml, dentro del arbol.
# Eso ensuciaria el worktree sin que nadie haya editado nada y el PR dejaria de
# ser limpio. Se redirigen a un temporal por corrida y se borran con trap: una
# limpieza al final del script no correria si la corrida muere por timeout o
# por senal, y el temporal si.
set -u

AQUI=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 126

if ! command -v forge >/dev/null 2>&1; then
    echo "capsula: forge no esta instalado; sin ejecutor no hay rojo ni verde (NO_MEDIDO)" >&2
    exit 127
fi

ARTEFACTOS=$(mktemp -d "${TMPDIR:-/tmp}/capsula-web3.XXXXXX") || exit 126
trap 'rm -rf "$ARTEFACTOS"' EXIT INT TERM HUP

case "${1:-}" in
    ataque)
        cd "$AQUI/vulnerable" || exit 126
        forge test --out "$ARTEFACTOS/out" --cache-path "$ARTEFACTOS/cache"
        exit $?
        ;;
    remediacion)
        cd "$AQUI/remediado" || exit 126
        forge test --out "$ARTEFACTOS/out" --cache-path "$ARTEFACTOS/cache"
        exit $?
        ;;
    *)
        echo "uso: correr.sh ataque|remediacion" >&2
        exit 64
        ;;
esac
