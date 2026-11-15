# defi-invariants

[![capsulas](https://github.com/alexisromtz-lab/defi-invariants/actions/workflows/capsulas.yml/badge.svg)](https://github.com/alexisromtz-lab/defi-invariants/actions/workflows/capsulas.yml)

Reproducciones mínimas de fallos matemáticos en protocolos DeFi. Cada caso trae
el contrato **vulnerable**, el **parche**, y una prueba que rompe el invariante en
uno y lo sostiene en el otro. Nada de reportes en prosa: el fallo se demuestra
ejecutando.

Estas cápsulas son material de estudio. Si te sirven para lo mismo, bienvenido.

## Requisito: Foundry

Necesitas `forge`. La primera corrida descarga el compilador de Solidity (`solc`),
así que hace falta red **una vez**.

```sh
curl -L https://foundry.paradigm.xyz | bash
~/.foundry/bin/foundryup
export PATH="$HOME/.foundry/bin:$PATH"
```

No hay dependencias de Solidity: las pruebas declaran a mano la dirección de los
cheatcodes de Foundry en lugar de usar `forge-std`, así que no hace falta
`forge install` ni vendorizar nada.

Sin `forge`, el ejecutor sale con **127** en vez de 1. Es a propósito: 127 es «no
encontrado» en POSIX, mientras que un 1 significaría «ataque exitoso» sin haber
ejecutado una sola línea.

## Cómo correr un caso

```sh
cd 001-inflacion-de-la-primera-accion
./correr.sh ataque        # rc != 0 : el invariante está roto
./correr.sh remediacion   # rc == 0 : el parche lo cierra
```

Rojo en uno y verde en el otro es la única prueba de que el parche cierra el
invariante que el ataque rompe, y no de que la prueba estaba mal escrita.

`correr.sh` redirige los artefactos de `forge` (`out/`, `cache/`) a un temporal que
se borra al salir: una corrida no debe dejar el árbol sucio.

## Verificación

El repositorio se verifica a sí mismo. Un solo comando comprueba la promesa de
arriba en todas las cápsulas:

```sh
./verificar-capsulas.sh
```

```
CAPSULA                                       ATAQUE  REMEDIO  VEREDICTO
001-inflacion-de-la-primera-accion            1       0        OK: [FAIL: acciones-positivas-por-deposito]
002-manipulacion-oraculo-spot-amm             1       0        OK: [FAIL: colateral-cubre-la-deuda]
003-contabilidad-interna-desincronizada       1       0        OK: [FAIL: contabilidad-cubierta-por-custodia]
ARBOL LIMPIO: ninguna corrida dejo out/, cache/ ni broadcast/
CAPSULAS: 0 fallo(s)
```

Corre en cada push (`.github/workflows/capsulas.yml`, `forge 1.9.0`), así que el
badge no es decoración: si una cápsula deja de romperse o deja de arreglarse, se
pone rojo.

**Qué exige, exactamente** — tres condiciones, no una:

1. el ataque sale **distinto de cero**;
2. y el `[FAIL: …]` que imprime **nombra el invariante**, comprobando que ese texto
   aparece literalmente en el archivo de ataque publicado. Un `assert(false)`
   imprime `panic: assertion failed` y **se rechaza**: un rojo anónimo puede ser una
   compilación rota disfrazada de invariante roto;
3. el parche sale **cero**.

Y una cuarta, sobre el árbol: la corrida no puede dejar `out/`, `cache/` ni
`broadcast/` dentro del repositorio.

El verificador **no duplica la lista de invariantes**: los lee de los propios
archivos publicados, así que no hay una segunda fuente de verdad que pueda
desincronizarse.

## Casos

| # | Caso | Invariante | Qué lo rompe |
|---|------|-----------|--------------|
| 001 | inflacion-de-la-primera-accion | `acciones_emitidas > 0` para todo depósito ≥ 1 wei | una donación directa al Vault infla el precio por acción y el depósito siguiente se redondea a cero |
| 002 | manipulacion-oraculo-spot-amm | `deuda ≤ colateral × precio_previo` | el precio spot de un pool se mueve y el mercado lo lee en el mismo bloque |
| 003 | contabilidad-interna-desincronizada | `saldos_contables ≤ custodia_real` | el libro anota el monto pedido y el token entrega menos: la comisión cae entera sobre el último que sale |

## 001 · Inflación de la primera acción

Un Vault emite acciones con división entera hacia abajo sobre las reservas
**previas**:

```
emitidas = (msg.value * totalShares) / activosPrevios
```

Con `totalShares` pequeño el denominador se puede inflar sin emitir nada a cambio:
una donación directa al contrato sube `totalAssets()` y no da acciones. El depósito
siguiente se redondea a cero:

```
(1 ether * 1) / (1 ether + 1) = 0 acciones
```

Quien depositó pagó y no recibió nada; quien donó se queda con su dinero al retirar
su única acción.

**El parche** no es un `require(emitidas > 0)`, que habría revertido el depósito de
la víctima —protección a costa de romper el contrato, no conservación del
invariante—. Es un cambio de la ecuación: acciones y activos **virtuales**, el
enfoque que no deja que el denominador sea pequeño nunca.

## 002 · Manipulación del oráculo spot de un AMM

La misma estructura, pero el fallo no está en el redondeo sino en **de dónde sale el
precio**. Un mercado de préstamo valora el colateral con el precio spot de un pool
`x*y=k`, y ese precio lo mueve cualquiera comprando dentro del mismo bloque.

El ataque completo, en una sola transacción: pedir prestado flash, comprar contra el
pool para inflar el spot, depositar colateral ya valorado al precio inflado, pedir
prestado el máximo, devolver el token al pool y cerrar el flash.

**El parche** ancla el precio: `precio()` deja de leer el spot y devuelve un ancla
que se sincroniza sin permisos, como mucho un 1 % por bloque.

El resultado interesante no es «presta menos», es que el ataque **no se paga**: la
ida y vuelta por el pool cuesta más de lo que el mercado presta, así que el atacante
no puede ni devolver el préstamo flash. Los dos lados comparan la misma cantidad
—`prestado + recuperado` contra el capital flash— y dan signos opuestos. Ese par es
la evidencia; el `require` del invariante es sólo su consecuencia.

**Límite declarado** del parche, en vez de escondido: la cota acota *cuánto* se mueve
el ancla por bloque, no impide un precio sostenido. Quien mantenga la reserva
manipulada durante ~200 bloques acaba moviendo el ancla hasta el precio manipulado.
El test `test_laCotaLimitaElBloquePeroNoElPrecioSostenido` lo publica.

## 003 · Contabilidad interna desincronizada

El fallo no está en el redondeo ni en el precio, sino en **qué se anota**. Una bóveda
acredita al depositante el monto que *pidió*, mientras el token entrega *menos*: la
comisión de transferencia se va por el camino sin que el libro interno se entere.

```solidity
saldos[msg.sender] += cuanto;   // lo pedido
// custodia real = token.balanceOf(address(this))  → lo que de verdad llegó
```

Diez depósitos de `100e18` sobre un token que quema un 1 % al moverse:

| | vulnerable | remediado |
|---|---|---|
| `totalContable` | 1000e18 | 990e18 |
| `custodia` | 990e18 | 990e18 |
| retiran completo | 9 de 10 | 10 de 10 |
| el décimo encuentra | 90e18 con saldo 100e18 | 0 |

El invariante que se rompe es de conservación, no de autorización:

```
suma_saldos_contables <= custodia_real
```

**El detalle que importa:** la comisión no es el fallo — es su **distribución**. Ese
1 % se acumula sobre quien quede último en salir, que descubre que su saldo dice 100
mientras la bóveda tiene 90. Los nueve primeros cobran completos; el que llega tarde
paga la fiesta.

**El parche** no es otro `require`. Acredita el delta medido:

```solidity
uint256 previo   = token.balanceOf(address(this));
token.transferirDe(msg.sender, address(this), cuanto);
uint256 recibido = token.balanceOf(address(this)) - previo;
saldos[msg.sender] += recibido;
```

Cero guardas nuevas: la corrección es aritmética. El atajo perezoso
—`require(recibido == cuanto)`— habría rechazado el token entero, es decir habría
vendido exclusión de tokens como si fuera contabilidad. El test
`test_elParcheNoRechazaElTokenConComision` lo falsa: el mismo token con comisión se
deposita y se retira completo bajo el parche.

**Límite declarado:** medir el delta asume que el token no mueve su propio
`balanceOf` a mitad de llamada. Un token con gancho de reentrada podría inflar el
saldo observado y volver a separar contabilidad de custodia.

## Qué es y qué no es

- **Es** material de estudio: reproducciones mínimas escritas desde cero. No copia
  código de ningún protocolo; reduce patrones públicos a lo mínimo expresable.
- **No es** un aviso de seguridad sobre ningún protocolo real, ni una herramienta de
  auditoría. Los contratos son deliberadamente pequeños para que el fallo quepa en
  una pantalla.

## Licencia

MIT — ver [LICENSE](LICENSE).
