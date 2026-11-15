#!/usr/bin/env bash
# Verifica cada capsula del repositorio con el predicado que el README promete:
# ataque rojo NOMBRADO y remediacion verde. No duplica el invariante: lo lee del
# propio archivo de ataque publicado.
#
# Cuatro condiciones, no una:
#   1. el ataque sale distinto de cero;
#   2. y su [FAIL: ...] nombra el invariante -- el texto aparece en la fuente publicada.
#      Un assert(false) imprime un panic anonimo y se rechaza: un rojo anonimo puede
#      ser una compilacion rota disfrazada de invariante roto;
#   3. el parche sale cero;
#   4. y ambas corridas EJECUTARON pruebas. Cero pruebas tambien sale cero, y leerlo
#      como verde seria medir la ausencia de la prueba, no su resultado.
#
# Y una quinta sobre el arbol: la corrida no deja out/, cache/ ni broadcast/ dentro.
set -u
fallos=0
printf '%-45s %-7s %-8s %-12s %s\n' CAPSULA ATAQUE REMEDIO PRUEBAS VEREDICTO
for dir in 0*/; do
  c=${dir%/}
  ataque_test=$(ls "$c"/vulnerable/test/*.t.sol 2>/dev/null | head -1)
  if [ -z "$ataque_test" ]; then
    printf '%-45s %-7s %-8s %-12s %s\n' "$c" '-' '-' '-' 'FALLA: sin prueba de ataque declarada'
    fallos=$((fallos+1)); continue
  fi

  salida=$(./"$c"/correr.sh ataque 2>&1); rc_ataque=$?
  rojas=$(printf '%s\n' "$salida" | grep -oE '[0-9]+ failed' | head -1 | grep -oE '^[0-9]+')
  marcador=''
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    if grep -qF -- "$m" "$ataque_test"; then marcador=$m; break; fi
  done < <(printf '%s\n' "$salida" | grep -oE '\[FAIL: [^]]+\]' | sed 's/^\[FAIL: //; s/\]$//' | grep -v '^panic')

  salida_p=$(./"$c"/correr.sh remediacion 2>&1); rc_remediacion=$?
  verdes=$(printf '%s\n' "$salida_p" | grep -oE '[0-9]+ passed' | head -1 | grep -oE '^[0-9]+')

  if [ "$rc_ataque" -eq 0 ]; then
    veredicto='FALLA: el ataque no rompe nada (rc=0)'
  elif [ "${rojas:-0}" -eq 0 ]; then
    veredicto='FALLA: el ataque no ejecuto ninguna prueba que fallara'
  elif [ -z "$marcador" ]; then
    veredicto='FALLA: rojo anonimo (sin [FAIL: <invariante>] en la fuente)'
  elif [ "$rc_remediacion" -ne 0 ]; then
    veredicto="FALLA: el parche no cierra (rc=$rc_remediacion)"
  elif [ "${verdes:-0}" -eq 0 ]; then
    veredicto='FALLA: el parche no ejecuto ninguna prueba que pasara'
  else
    veredicto="OK: [FAIL: $marcador]"
  fi
  case "$veredicto" in OK*) ;; *) fallos=$((fallos+1));; esac
  printf '%-45s %-7s %-8s %-12s %s\n' "$c" "$rc_ataque" "$rc_remediacion" "${rojas:-0}roja/${verdes:-0}verde" "$veredicto"
done

residuo=$(find . -path ./.git -prune -o -type d \( -name out -o -name cache -o -name broadcast \) -print)
if [ -n "$residuo" ]; then
  echo "FALLA: la corrida dejo artefactos dentro del arbol:"; printf '%s\n' "$residuo"; fallos=$((fallos+1))
else
  echo "ARBOL LIMPIO: ninguna corrida dejo out/, cache/ ni broadcast/"
fi
echo "CAPSULAS: $fallos fallo(s)"
exit $([ "$fallos" -eq 0 ] && echo 0 || echo 1)
