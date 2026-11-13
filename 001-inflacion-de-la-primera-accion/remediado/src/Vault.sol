// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Vault — version REMEDIADA del caso `inflacion-de-la-primera-accion`.
/// @notice La misma reproduccion minima, con el parche: acciones y activos
///         virtuales. El denominador nunca es pequeno, asi que la donacion
///         directa no puede diluir el deposito siguiente hasta cero.
/// @dev La remediacion no es un `require` sobre el resultado: es un cambio de
///      la ecuacion. Un `require(emitidas > 0)` habria revertido el deposito de
///      la victima -- proteccion a costa de romper el contrato, no conservacion
///      del invariante.
contract Vault {
    uint256 private constant ACCIONES_VIRTUALES = 1e3;
    uint256 private constant ACTIVOS_VIRTUALES = 1;

    uint256 public totalShares;
    mapping(address => uint256) public shares;

    function totalAssets() public view returns (uint256) {
        return address(this).balance;
    }

    /// @dev La donacion directa se acepta igual que en la version vulnerable: el
    ///      parche no puede consistir en prohibir el ataque, solo en sobrevivirlo.
    receive() external payable {}

    function depositar() external payable returns (uint256 emitidas) {
        uint256 activosPrevios = totalAssets() - msg.value;
        emitidas = (msg.value * (totalShares + ACCIONES_VIRTUALES)) / (activosPrevios + ACTIVOS_VIRTUALES);
        shares[msg.sender] += emitidas;
        totalShares += emitidas;
    }

    function retirar(uint256 cantidad) external returns (uint256 activos) {
        activos = (cantidad * (totalAssets() + ACTIVOS_VIRTUALES)) / (totalShares + ACCIONES_VIRTUALES);
        shares[msg.sender] -= cantidad;
        totalShares -= cantidad;
        (bool ok, ) = payable(msg.sender).call{value: activos}("");
        require(ok, "transferencia fallida");
    }
}
