// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBondingCurve {

    function INITIAL_TOKEN_BALANCE() external view returns (uint256);
    function INITIAL_RESERVE_BALANCE() external view returns (uint256);
    function CURVE_WEIGHT() external view returns (uint32);

    function calculatePurchaseReturn(
        uint256 _supply,
        uint256 _connectorBalance,
        uint32 _connectorWeight,
        uint256 _depositAmount
    ) external view returns (uint256);

    function calculateSaleReturn(
        uint256 _supply,
        uint256 _connectorBalance,
        uint32 _connectorWeight,
        uint256 _sellAmount
    ) external view returns (uint256);
}
