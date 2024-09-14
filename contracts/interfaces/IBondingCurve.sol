// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBondingCurve {
    // v1
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

    // v2
    function VIRTUAL_ETH_RESERVE() external view returns (uint256);
    function VIRTUAL_TOKEN_SUPPLY() external view returns (uint256);
    function K() external view returns (uint256);
    function INITIAL_TOKEN_SUPPLY() external view returns (uint256);
    function VIRTUAL_TOKEN_LOCKED() external view returns (uint256);
    function PRICE_PRECISION() external view returns (uint256);
    function VERSION() external view returns (uint8);
    
    function calculatePurchaseReturn(uint256 ethReserve_, uint256 tokenReserve_, uint256 ethToBuy_) external view returns (uint256);
    function calculateSaleReturn(uint256 ethReserve_, uint256 tokenReserve_, uint256 tokenToSell_) external view returns (uint256);
    function getTokenPrice(uint256 ethReserve) external view returns (uint256);
}