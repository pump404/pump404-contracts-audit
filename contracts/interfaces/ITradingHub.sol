// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITradingHub {

    struct InputData {
        // token to swap from, address(0) means ETH, tokenIn and tokenOut cannot be the same
        address tokenIn;
        // token to swap to, address(0) means ETH
        address tokenOut;
        // recipient of the swapped token
        address recipient;
        // amount of token to swap
        uint256 amountIn;
        // minimum amount of token to receive
        uint256 amountOutMinimum;
    }

    event BoughtToken(address indexed buyer, address indexed token, uint256 amount, uint256 cost);
    event SoldToken(address indexed seller, address indexed token, uint256 amount, uint256 cost);
    event Swapped(address indexed sender, address indexed recipient, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event SentToUniswapV3(address indexed erc404_token, address uinswap_v3_pool, uint256 LP_tokenId, uint256 liquidity, uint256 amount0, uint256 amount1, uint256 ignition_fee);

    function VERSION() external view returns (uint8);
    function tradingFeeRate() external view returns (uint32);
    function DENOMINATOR() external view returns (uint32);
    function treasuryAddress() external view returns (address);
    function launchHubAddress() external view returns (address);
    function tokenInAssetPool(address token_) external view returns (address);
    function MINIMUM_ETH_BUY() external view returns (uint256);
    function lockedAssetPoolAddress() external view returns (address);

    function setTokenInAssetPool(address token_, address asset_pool_) external;

    function calculatePurchaseReturn(address tokenAddress_, uint256 eth_amount_)  external view returns(uint256);

    function calculateSaleReturn(address tokenAddress_, uint256 token_amount_) external view returns(uint256);

    function swap(InputData calldata input_data_) external payable;

    function sendToUniswapV3(address tokenAddress_, uint160 sqrtPriceX96_, int24 tickLower, int24 tickUpper) external;

    function setUserToErc404Exempt(address erc404_address_, address user_address_, bool is_exempt_) external;
}
