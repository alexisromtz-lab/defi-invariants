// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Token — ERC20 minimo del caso `manipulacion-oraculo-spot-amm`.
/// @notice Reproduccion minima escrita por Platino Labs. No copia codigo de
///         ningun protocolo: reduce el patron publico a lo minimo expresable.
/// @dev Sin `approve`/`allowance`: el sujeto de esta capsula es el oraculo, no
///      el token. La maquinaria de allowances no anadiria una linea al
///      invariante y haria el ataque mas dificil de leer.
contract Token {
    mapping(address => uint256) public balanceOf;

    function acunar(address quien, uint256 cuanto) external {
        balanceOf[quien] += cuanto;
    }

    function transferir(address a, uint256 cuanto) external returns (bool) {
        require(balanceOf[msg.sender] >= cuanto, "saldo insuficiente");
        balanceOf[msg.sender] -= cuanto;
        balanceOf[a] += cuanto;
        return true;
    }

    function transferirDe(address de, address a, uint256 cuanto) external returns (bool) {
        require(balanceOf[de] >= cuanto, "saldo insuficiente");
        balanceOf[de] -= cuanto;
        balanceOf[a] += cuanto;
        return true;
    }
}

/// @title Pool — producto constante x * y = k.
/// @dev El oraculo ES este `precioSpot`: reservaStable / reservaToken leidos en
///      el instante. No es una simplificacion del fallo, es el fallo.
contract Pool {
    Token public immutable token;
    Token public immutable stable;

    uint256 public reservaToken;
    uint256 public reservaStable;

    constructor(Token token_, Token stable_) {
        token = token_;
        stable = stable_;
    }

    /// Cuanto stable vale UN token entero, expresado en 1e18.
    function precioSpot() public view returns (uint256) {
        if (reservaToken == 0) return 0;
        return (reservaStable * 1e18) / reservaToken;
    }

    function agregarLiquidez(uint256 cToken, uint256 cStable) external {
        token.transferirDe(msg.sender, address(this), cToken);
        stable.transferirDe(msg.sender, address(this), cStable);
        reservaToken += cToken;
        reservaStable += cStable;
    }

    /// Paga stable, recibe token: la reserva de token baja y el precio SUBE.
    function comprarToken(uint256 stableIn) external returns (uint256 tokenOut) {
        tokenOut = (reservaToken * stableIn) / (reservaStable + stableIn);
        stable.transferirDe(msg.sender, address(this), stableIn);
        reservaStable += stableIn;
        reservaToken -= tokenOut;
        token.transferir(msg.sender, tokenOut);
    }

    /// Paga token, recibe stable: la reserva de token sube y el precio BAJA.
    function venderToken(uint256 tokenIn) external returns (uint256 stableOut) {
        stableOut = (reservaStable * tokenIn) / (reservaToken + tokenIn);
        token.transferirDe(msg.sender, address(this), tokenIn);
        reservaToken += tokenIn;
        reservaStable -= stableOut;
        stable.transferir(msg.sender, stableOut);
    }
}

/// @title Mercado — prestamos contra colateral valorado por el Pool.
/// @notice Version VULNERABLE: el tope de prestamo se calcula con el precio spot
///         leido en el mismo bloque en que el deudor puede mover ese precio. El
///         colateral no cambia de valor; cambia lo que el mercado cree que vale.
contract Mercado {
    uint256 public constant LTV_BPS = 7500; // 75 %

    Pool public immutable pool;
    Token public immutable stable;

    uint256 public reservaStable;
    mapping(address => uint256) public colateral;
    mapping(address => uint256) public deuda;

    constructor(Pool pool_, Token stable_) {
        pool = pool_;
        stable = stable_;
    }

    function fondear(uint256 cuanto) external {
        stable.transferirDe(msg.sender, address(this), cuanto);
        reservaStable += cuanto;
    }

    function precio() public view returns (uint256) {
        return pool.precioSpot();
    }

    function depositarColateral(uint256 cuanto) external {
        pool.token().transferirDe(msg.sender, address(this), cuanto);
        colateral[msg.sender] += cuanto;
    }

    function tope(address quien) external view returns (uint256) {
        return _tope(quien);
    }

    function _tope(address quien) internal view returns (uint256) {
        return (colateral[quien] * precio() / 1e18) * LTV_BPS / 10_000;
    }

    function prestar(uint256 cuanto) external {
        require(deuda[msg.sender] + cuanto <= _tope(msg.sender), "limite de prestamo");
        require(reservaStable >= cuanto, "sin liquidez");
        deuda[msg.sender] += cuanto;
        reservaStable -= cuanto;
        stable.transferir(msg.sender, cuanto);
    }
}
