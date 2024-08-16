// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILockedAssetPool {

    function launchHubAddress() external view returns (address);

    function approveAsset(address asset_) external;
    function sendToUniswapV3(address tokenAddress_, uint160 sqrtPriceX96_, int24 tickLower, int24 tickUpper) external returns(uint256, uint128, address, uint256, uint256, uint256);
    function getAssetBalance(address asset_) external view returns (uint256);
}
