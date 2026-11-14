// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title TokenConComision — ERC20 minimo que cobra peaje al moverse.
/// @notice Reproduccion escrita por Platino Labs. No copia codigo de ningun
///         protocolo: reduce a lo minimo expresable una propiedad que EIP-20 NO
///         promete — que el receptor reciba exactamente lo que el emisor envia.
///         El estandar fija que `transfer` mueva un importe; no fija que ese
///         importe llegue entero al otro lado.
/// @dev La comision se quema en vez de ir a un tesoro. Es equivalente para este
///      caso: lo que rompe la contabilidad es que `balanceOf(receptor)` suba
///      MENOS de lo que baja `balanceOf(emisor)`, y quien se quede la comision
///      no cambia ninguna cuenta del invariante.
contract TokenConComision {
    uint256 public constant BPS = 10_000;

    uint256 public immutable comisionBps;
    mapping(address => uint256) public balanceOf;

    constructor(uint256 comisionBps_) {
        require(comisionBps_ < BPS, "comision imposible");
        comisionBps = comisionBps_;
    }

    function acunar(address quien, uint256 cuanto) external {
        balanceOf[quien] += cuanto;
    }

    function transferir(address a, uint256 cuanto) external returns (bool) {
        return _mover(msg.sender, a, cuanto);
    }

    /// @dev Sin `allowance`: el sujeto de esta capsula es la contabilidad de la
    ///      boveda, no la maquinaria de permisos. Un `approve` no anadiria ni
    ///      una linea al invariante y haria el ataque mas dificil de leer.
    function transferirDe(address de, address a, uint256 cuanto) external returns (bool) {
        return _mover(de, a, cuanto);
    }

    function _mover(address de, address a, uint256 cuanto) internal returns (bool) {
        require(balanceOf[de] >= cuanto, "saldo insuficiente");
        balanceOf[de] -= cuanto;
        balanceOf[a] += cuanto - (cuanto * comisionBps) / BPS;
        return true;
    }
}

/// @title Boveda — version VULNERABLE del caso `contabilidad-interna-desincronizada`.
/// @notice Custodia un token y lleva su propia contabilidad por depositante. El
///         libro se escribe con el importe que el depositante PIDE mover.
/// @dev El fallo no es la comision: es que la boveda anota en su libro un
///      importe que ella no decide. Quien decide cuanto entra de verdad es el
///      token, y su `transfer` solo promete mover, no entregar.
contract Boveda {
    TokenConComision public immutable token;

    mapping(address => uint256) public saldos;
    uint256 public totalContable;

    constructor(TokenConComision token_) {
        token = token_;
    }

    function depositar(uint256 cuanto) external {
        token.transferirDe(msg.sender, address(this), cuanto);
        saldos[msg.sender] += cuanto;
        totalContable += cuanto;
    }

    function retirar(uint256 cuanto) external {
        require(saldos[msg.sender] >= cuanto, "saldo contable");
        saldos[msg.sender] -= cuanto;
        totalContable -= cuanto;
        token.transferir(msg.sender, cuanto);
    }

    function custodia() external view returns (uint256) {
        return token.balanceOf(address(this));
    }
}
