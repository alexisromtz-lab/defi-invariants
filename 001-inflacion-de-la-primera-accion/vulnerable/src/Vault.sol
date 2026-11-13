// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Vault — version VULNERABLE del caso `inflacion-de-la-primera-accion`.
/// @notice Reproduccion minima escrita por Platino Labs. No copia codigo de
///         ningun protocolo: reduce el patron publico a lo minimo expresable.
/// @dev `depositar` emite acciones con division entera hacia ABAJO sobre las
///      reservas previas. Con `totalShares` pequeno, una donacion directa al
///      contrato infla el denominador y el deposito siguiente se redondea a
///      CERO acciones: quien deposita pierde su dinero y quien dono se lo queda.
contract Vault {
    uint256 public totalShares;
    mapping(address => uint256) public shares;

    function totalAssets() public view returns (uint256) {
        return address(this).balance;
    }

    /// @dev La donacion directa ES el ataque, no un accidente del test: sin esta
    ///      entrada la donacion revierte y el caso no se puede ni plantear.
    receive() external payable {}

    function depositar() external payable returns (uint256 emitidas) {
        uint256 activosPrevios = totalAssets() - msg.value;
        if (totalShares == 0) {
            emitidas = msg.value;
        } else {
            emitidas = (msg.value * totalShares) / activosPrevios;
        }
        shares[msg.sender] += emitidas;
        totalShares += emitidas;
    }

    function retirar(uint256 cantidad) external returns (uint256 activos) {
        activos = (cantidad * totalAssets()) / totalShares;
        shares[msg.sender] -= cantidad;
        totalShares -= cantidad;
        (bool ok, ) = payable(msg.sender).call{value: activos}("");
        require(ok, "transferencia fallida");
    }
}
