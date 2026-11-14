// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Boveda, TokenConComision} from "../src/Boveda.sol";

contract Depositante {
    function depositar(Boveda boveda, uint256 cuanto) external {
        boveda.depositar(cuanto);
    }

    function retirar(Boveda boveda, uint256 cuanto) external {
        boveda.retirar(cuanto);
    }

    function retirarTodo(Boveda boveda) external {
        boveda.retirar(boveda.saldos(address(this)));
    }
}

/// INVARIANTE `contabilidad-cubierta-por-custodia`:
///     suma_saldos_contables <= custodia_real
///
/// El MISMO escenario que en `vulnerable/`. Aqui TIENE QUE PASAR: rojo alli y
/// verde aqui es lo unico que prueba que el parche cierra el invariante que el
/// ataque rompe, y no que la prueba de alla estaba mal escrita.
contract PruebaRemediacion {
    uint256 constant DEPOSITO = 100e18;
    uint256 constant DEPOSITANTES = 10;

    TokenConComision token;
    Boveda boveda;
    Depositante[] gente;

    function setUp() public {
        token = new TokenConComision(100);
        boveda = new Boveda(token);

        for (uint256 i = 0; i < DEPOSITANTES; i++) {
            Depositante d = new Depositante();
            token.acunar(address(d), DEPOSITO);
            gente.push(d);
        }
    }

    function test_elLibroNoPuedePrometerMasDeLoQueLaBovedaGuarda() public {
        for (uint256 i = 0; i < DEPOSITANTES; i++) {
            gente[i].depositar(boveda, DEPOSITO);
        }

        // El libro ya no promete 1 000: anota 990, que es exactamente lo que
        // entro. La comision no desaparece; deja de estar prometida.
        assert(boveda.totalContable() == DEPOSITO * DEPOSITANTES * 99 / 100);
        assert(boveda.custodia() == boveda.totalContable());

        // Nadie queda colgado: los diez cobran lo anotado, y el que llega
        // ultimo no hereda el peaje de los demas.
        for (uint256 i = 0; i < DEPOSITANTES; i++) {
            gente[i].retirarTodo(boveda);
        }
        assert(boveda.totalContable() == 0);
        assert(boveda.custodia() == 0);

        // INVARIANTE: ahora se sostiene, y lo hace por construccion.
        require(
            boveda.totalContable() <= boveda.custodia(), "contabilidad-cubierta-por-custodia"
        );
    }

    /// @dev El falsador de la condicion que arrastraba esta capsula: el parche NO
    ///      puede ser otra guarda. Si el remedio hubiera sido el atajo
    ///      `require(recibido == cuanto)`, este deposito revertiria y la capsula
    ///      estaria vendiendo exclusion de tokens como diseno contable. Aqui
    ///      pasa, y el libro anota 99: la boveda acepta el token con comision y
    ///      deja de prometer lo que no tiene.
    function test_elParcheNoRechazaElTokenConComision() public {
        gente[0].depositar(boveda, DEPOSITO);
        assert(boveda.saldos(address(gente[0])) == 99e18);
        assert(boveda.totalContable() == boveda.custodia());
    }
}
