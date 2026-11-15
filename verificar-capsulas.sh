#!/usr/bin/env bash
# Verifica cada capsula del repositorio con el predicado que el README promete:
# ataque rojo NOMBRADO y remediacion verde. No duplica el invariante: lo lee del
# propio archivo de ataque publicado.
set -u
fallos=0
printf '%-45s %-7s %-8s %s\n' CAPSULA ATAQUE REMEDIO VEREDICTO
for dir in 0*/; do
  c=${dir%/}
  ataque_test=$(ls "$c"/vulnerable/test/*.t.sol 2>/dev/null | head -1)
  if [ -z "$ataque_test" ]; then
    printf '%-45s %-7s %-8s %s\n' "$c" '-' '-' 'FALLA: sin prueba de ataque declarada'
    fallos=$((fallos+1)); continue
  fi
  salida=$(./"$c"/correr.sh ataque 2>&1); rc_ataque=$?
  marcador=''
  if [ "$rc_ataque" -ne 0 ]; then
    while IFS= read -r m; do
      [ -z "$m" ] && continue
      if grep -qF -- "$m" "$ataque_test"; then marcador=$m; break; fi
    done < <(printf '%s\n' "$salida" | grep -oE '\[FAIL: [^]]+\]' | sed 's/^\[FAIL: //; s/\]$//' | grep -v '^panic')
  fi
  ./"$c"/correr.sh remediacion >/tmp/remed.log 2>&1; rc_remediacion=$?
  if [ "$rc_ataque" -eq 0 ]; then
    veredicto='FALLA: el ataque no rompe nada (rc=0)'
  elif [ -z "$marcador" ]; then
    veredicto='FALLA: rojo anonimo (sin [FAIL: <invariante>] en la fuente)'
  elif [ "$rc_remediacion" -ne 0 ]; then
    veredicto="FALLA: el parche no cierra (rc=$rc_remediacion)"
  else
    veredicto="OK: [FAIL: $marcador]"
  fi
  case "$veredicto" in OK*) ;; *) fallos=$((fallos+1));; esac
  printf '%-45s %-7s %-8s %s\n' "$c" "$rc_ataque" "$rc_remediacion" "$veredicto"
done
residuo=$(find . -path ./.git -prune -o -type d \( -name out -o -name cache -o -name broadcast \) -print)
if [ -n "$residuo" ]; then
  echo "FALLA: la corrida dejo artefactos dentro del arbol:"; printf '%s\n' "$residuo"; fallos=$((fallos+1))
else
  echo "ARBOL LIMPIO: ninguna corrida dejo out/, cache/ ni broadcast/"
fi
echo "CAPSULAS: $fallos fallo(s)"
exit $([ "$fallos" -eq 0 ] && echo 0 || echo 1)
