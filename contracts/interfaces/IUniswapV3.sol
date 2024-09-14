// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUniswapV3 {
    event TradingFeeRateChanged(uint24 trading_fee);
    event TreasuryAddressChanged(address treasury_address);
    event Swapped(address indexed in_token_address, address indexed out_token_address, address to_user_address, uint256 in_amount, uint256 out_amount, uint256 fee_amount);

    function getPool(address token0_address, address token1_address) external view returns (address, uint24);
    function getOutTokenAmountFromInTokenAmount(address in_token_address, address out_token_address, uint256 in_amount) external;

    function swap(address from_token_address, address to_token_address, uint256 in_amount, uint256 out_amount_min) external payable;
}
