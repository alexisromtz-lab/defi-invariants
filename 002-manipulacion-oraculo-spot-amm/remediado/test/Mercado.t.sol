// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Token, Pool, Mercado} from "../src/Mercado.sol";

/// @dev Direccion documentada de los cheatcodes de Foundry. Se declara aqui
///      para que la capsula no dependa de `forge-std`: una capsula que exige
///      `forge install` no corre en una maquina limpia.
interface Vm {
    function roll(uint256 altura) external;
}

Vm constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

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

    function intentarPrestar(Mercado mercado, uint256 cuanto) external returns (bool ok) {
        (ok, ) = address(mercado).call(abi.encodeWithSignature("prestar(uint256)", cuanto));
    }

    function sincronizar(Mercado mercado) external {
        mercado.sincronizar();
    }

    function tapa(Mercado mercado) external view returns (uint256) {
        return mercado.tope(address(this));
    }

    function intentarDevolver(Token stable, address a, uint256 cuanto) external returns (bool ok) {
        (ok, ) = address(stable).call(abi.encodeWithSignature("transferir(address,uint256)", a, cuanto));
    }
}

/// INVARIANTE `colateral-cubre-la-deuda`:
///     deuda_emitida <= valor_del_colateral * precio_previo_al_ataque
///
/// El MISMO ataque que en `vulnerable/`. Aqui TIENE QUE PASAR: rojo alli y verde
/// aqui es lo unico que prueba que el parche cierra el invariante que el ataque
/// rompe, y no que la prueba de alla estaba mal escrita.
contract PruebaRemediacion {
    Token token;
    Token stable;
    Pool pool;
    Mercado mercado;
    Actor atacante;

    uint256 constant CAPITAL_FLASH = 900_000e18;
    uint256 constant COLATERAL = 100e18;
    address constant PRESTAMISTA = address(0xB0B);

    function setUp() public {
        token = new Token();
        stable = new Token();
        pool = new Pool(token, stable);

        token.acunar(address(this), 1_000e18);
        stable.acunar(address(this), 1_500_000e18);
        pool.agregarLiquidez(1_000e18, 1_000_000e18);

        // el ancla nace del precio real del pool, asi que el pool tiene que
        // tener liquidez antes de que el mercado exista
        mercado = new Mercado(pool, stable);
        mercado.fondear(500_000e18);

        atacante = new Actor();
        stable.acunar(address(atacante), CAPITAL_FLASH);

        // el mercado lleva tiempo desplegado: sin esto `sincronizar` chocaria
        // con el constructor y el limite medido seria el de arranque, no el de
        // regimen -- un verde que no dice nada sobre el mercado en produccion
        VM.roll(block.number + 100);
    }

    function test_elPrecioDelMismoBloqueNoPuedeValorarElColateral() public {
        uint256 precioAntes = mercado.precio();

        uint256 comprados = atacante.comprar(pool, CAPITAL_FLASH);
        atacante.depositar(mercado, COLATERAL);

        // el atacante intenta ademas mover el ancla dentro del mismo bloque:
        // puede, pero solo un 1 %
        atacante.sincronizar(mercado);
        assert(mercado.precio() <= (precioAntes * 10_100) / 10_000);

        // el importe que el ataque pedia en la version vulnerable, calculado
        // con el spot manipulado, ahora tiene que ser rechazado
        uint256 inflado = (COLATERAL * pool.precioSpot() / 1e18) * 7500 / 10_000;
        bool acepto = atacante.intentarPrestar(mercado, inflado);
        assert(!acepto);
        assert(mercado.deuda(address(atacante)) == 0);

        // lo maximo que el mercado acepta con el precio acotado
        uint256 prestado = atacante.tapa(mercado);
        atacante.prestar(mercado, prestado);

        // el atacante devuelve el token al pool, igual que en `vulnerable/`
        uint256 recuperado = atacante.vender(pool, comprados - COLATERAL);

        // la misma suma que alla pagaba el ataque aqui se queda corta: la ida y
        // vuelta por el pool cuesta mas de lo que el mercado presta, asi que no
        // hay forma de devolver el flash. El ataque falla por economia, no
        // porque un `require` lo rechace.
        assert(prestado + recuperado < CAPITAL_FLASH);
        assert(!atacante.intentarDevolver(stable, PRESTAMISTA, CAPITAL_FLASH));

        uint256 valorAlPrecioPrevio = mercado.colateral(address(atacante)) * precioAntes / 1e18;

        // INVARIANTE: ahora se sostiene. El mercado presto como mucho contra el
        // precio que el atacante no pudo fijar.
        require(
            mercado.deuda(address(atacante)) <= valorAlPrecioPrevio, "colateral-cubre-la-deuda"
        );
    }

    /// @dev LIMITE DECLARADO del parche, no una virtud: la cota acota CUANTO se
    ///      mueve el ancla por bloque, no impide un precio sostenido. Quien
    ///      mantenga la reserva manipulada 200 bloques acaba moviendo el ancla
    ///      hasta el precio manipulado. Se publica porque un parche que solo se
    ///      anuncia por lo que arregla obliga al lector a descubrir solo lo que
    ///      no arregla.
    function test_laCotaLimitaElBloquePeroNoElPrecioSostenido() public {
        atacante.comprar(pool, CAPITAL_FLASH);
        uint256 manipulado = pool.precioSpot();

        for (uint256 i = 0; i < 200; i++) {
            VM.roll(block.number + 1);
            mercado.sincronizar();
        }

        assert(mercado.precio() == manipulado);
    }
}
