// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vault} from "../src/Vault.sol";

/// @dev La MISMA prueba que en `vulnerable/`, sobre el contrato remediado. El
///      ataque no cambia: si cambiara, el verde no diria nada sobre el parche,
///      solo sobre otra prueba.
interface Vm {
    function deal(address quien, uint256 cuanto) external;
}

Vm constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

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

    function balance() external view returns (uint256) {
        return address(this).balance;
    }
}

/// INVARIANTE `acciones-positivas-por-deposito`:
///     shares_emitidas(depositante) > 0   para todo deposito de al menos 1 wei
///
/// En la version remediada TIENE QUE PASAR. Rojo en `vulnerable/` y verde aqui
/// es lo unico que prueba que el parche cierra el invariante que el ataque rompe.
contract PruebaRemediacion {
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
        atacante.depositar{value: 1}(vault);
        atacante.donar(vault, 1 ether);
        victima.depositar{value: 1 ether}(vault);

        // INVARIANTE: con acciones virtuales el denominador nunca es pequeno y
        // el deposito de la victima emite acciones.
        assert(vault.shares(address(victima)) > 0);
    }

    function test_elAtacanteNoSeLlevaElDepositoAjeno() public {
        atacante.depositar{value: 1}(vault);
        atacante.donar(vault, 1 ether);
        victima.depositar{value: 1 ether}(vault);

        // el atacante aporto 1 ether + 1 wei y le quedaba 1 ether: si pudiera
        // retirar mas que su aporte mas su resto, el parche no cierra el ataque
        atacante.retirar(vault, vault.shares(address(atacante)));
        assert(atacante.balance() <= 2 ether);
    }
}
