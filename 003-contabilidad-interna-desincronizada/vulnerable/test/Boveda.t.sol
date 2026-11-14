// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Boveda, TokenConComision} from "../src/Boveda.sol";

/// @dev Un depositante por contrato para que `msg.sender` sea distinto sin
///      cheatcodes: esta capsula no necesita `prank` ni `forge-std`.
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

    /// @dev Devuelve si la boveda pudo pagar, en vez de reventar la prueba: un
    ///      revert del token es el sintoma, no el invariante.
    function intentarRetirarTodo(Boveda boveda) external returns (bool ok) {
        (ok, ) = address(boveda).call(
            abi.encodeWithSignature("retirar(uint256)", boveda.saldos(address(this)))
        );
    }
}

/// INVARIANTE `contabilidad-cubierta-por-custodia`:
///     suma_saldos_contables <= custodia_real
///
/// La boveda puede repartir como quiera, pero su libro no puede prometer MAS de
/// lo que guarda. Esta prueba AFIRMA el invariante: en la version vulnerable
/// TIENE QUE FALLAR, y su rojo es la capsula funcionando, no la suite rota.
contract PruebaAtaque {
    uint256 constant DEPOSITO = 100e18;
    uint256 constant DEPOSITANTES = 10;

    TokenConComision token;
    Boveda boveda;
    Depositante[] gente;

    function setUp() public {
        // 1 % de peaje en cada movimiento: el token entrega 99 de cada 100
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

        // La boveda anota 1 000 y guarda 990: la diferencia son las diez
        // comisiones, un 1 % de cada deposito que nunca entro.
        assert(boveda.totalContable() == DEPOSITO * DEPOSITANTES);
        assert(boveda.custodia() == DEPOSITO * DEPOSITANTES * 99 / 100);

        // Los nueve primeros cobran enteros, porque llegan antes de que la caja
        // se vacie...
        for (uint256 i = 0; i < DEPOSITANTES - 1; i++) {
            gente[i].retirarTodo(boveda);
        }

        // ...y el que llega ultimo encuentra 90 donde su libro dice 100. El peaje
        // acumulado de todos cae entero sobre una sola persona: el invariante no
        // se rompe por el 1 %, se rompe por quien lo paga.
        assert(boveda.saldos(address(gente[DEPOSITANTES - 1])) == DEPOSITO);
        assert(boveda.custodia() == 90e18);
        assert(!gente[DEPOSITANTES - 1].intentarRetirarTodo(boveda));

        // INVARIANTE: aqui revierte. La boveda promete 100 y custodia 90, y no
        // queda ningun movimiento futuro que pueda cerrar esa diferencia.
        require(
            boveda.totalContable() <= boveda.custodia(), "contabilidad-cubierta-por-custodia"
        );
    }
}
