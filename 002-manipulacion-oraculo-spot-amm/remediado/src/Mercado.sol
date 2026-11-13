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
/// @dev El pool NO se toca en la remediacion: el fallo no esta en el mercado de
///      producto constante, esta en creerle su precio instantaneo.
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

/// @title Mercado — version REMEDIADA del caso `manipulacion-oraculo-spot-amm`.
/// @notice El precio que el mercado USA para valorar colateral nunca es el spot
///         del instante: es un ancla que solo puede moverse un 1 % por bloque y
///         como mucho una vez por bloque. La forma canonica de la misma ley es
///         un TWAP; la cota por bloque es su forma minima y conserva la
///         propiedad que importa aqui: dentro de un bloque el deudor no puede
///         fijar el precio contra el que pide prestado.
/// @dev La remediacion no prohibe el swap ni congela el pool. Prohibir el
///      ataque no es cerrar el invariante: es romper el mercado para que el
///      invariante no se pueda plantear.
contract Mercado {
    uint256 public constant LTV_BPS = 7500; // 75 %
    uint256 public constant DELTA_MAX_BPS = 100; // 1 % por bloque

    Pool public immutable pool;
    Token public immutable stable;

    uint256 public reservaStable;
    uint256 public precioAncla;
    uint256 public ultimoBloque;

    mapping(address => uint256) public colateral;
    mapping(address => uint256) public deuda;

    constructor(Pool pool_, Token stable_) {
        pool = pool_;
        stable = stable_;
        precioAncla = pool_.precioSpot();
        ultimoBloque = block.number;
    }

    function fondear(uint256 cuanto) external {
        stable.transferirDe(msg.sender, address(this), cuanto);
        reservaStable += cuanto;
    }

    /// Acerca el ancla al spot real, como mucho un 1 % por bloque.
    function sincronizar() external {
        require(block.number > ultimoBloque, "una vez por bloque");
        ultimoBloque = block.number;

        uint256 bruto = pool.precioSpot();
        uint256 techo = (precioAncla * (10_000 + DELTA_MAX_BPS)) / 10_000;
        uint256 piso = (precioAncla * (10_000 - DELTA_MAX_BPS)) / 10_000;

        if (bruto > techo) {
            precioAncla = techo;
        } else if (bruto < piso) {
            precioAncla = piso;
        } else {
            precioAncla = bruto;
        }
    }

    function precio() public view returns (uint256) {
        return precioAncla;
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
