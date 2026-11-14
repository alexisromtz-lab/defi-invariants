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

/// @title Boveda — version REMEDIADA del caso `contabilidad-interna-desincronizada`.
/// @notice El libro se escribe con lo que la boveda OBSERVO entrar, no con lo
///         que el depositante dijo mover.
/// @dev El parche es aritmetico, no una guarda: no hay un solo `require` nuevo.
///      La cantidad acreditada deja de ser un parametro que la boveda no
///      controla y pasa a ser una diferencia que ella misma mide. Con eso el
///      libro no puede adelantarse a la custodia, porque ambos nacen del mismo
///      saldo observado.
/// @dev LIMITE DECLARADO, no una virtud: medir la diferencia asume que el token
///      no puede mover su propio `balanceOf` a mitad de la llamada. Un token con
///      gancho de reentrada podria inflar el saldo observado y volver a separar
///      el libro de la custodia. Esta capsula no trata ese caso; lo publica para
///      que el lector no lo descubra solo.
contract Boveda {
    TokenConComision public immutable token;

    mapping(address => uint256) public saldos;
    uint256 public totalContable;

    constructor(TokenConComision token_) {
        token = token_;
    }

    function depositar(uint256 cuanto) external {
        uint256 previo = token.balanceOf(address(this));
        token.transferirDe(msg.sender, address(this), cuanto);
        uint256 recibido = token.balanceOf(address(this)) - previo;
        saldos[msg.sender] += recibido;
        totalContable += recibido;
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
