// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "./ITradingHub.sol";

interface ILaunchHub {

    event LaunchedERC404(address indexed asset_pool, address bonding_curve, address erc404_token, address creator, uint256 initial_buy_amount, address operator);
    event SentToUniswapV3(address indexed erc404_token, address uinswap_v3_pool, uint256 LP_tokenId, uint256 liquidity, uint256 amount0, uint256 amount1, uint256 ignition_fee);

    function launchFee() external view returns (uint256);
    function ignitionFee() external view returns (uint256);
    function lockedPoolAddress() external view returns (address);
    function treasuryAddress() external view returns (address);
    function erc404Operator() external view returns (address);

    function tradingHub() external view returns (ITradingHub);

    function launchErc404(string memory name_, string memory symbol_, string memory defaultBaseURI_, uint256 initial_buy_amount_) external payable;
    function sendToUniswapV3(address tokenAddress_, uint160 sqrtPriceX96_, int24 tickLower, int24 tickUpper) external;
}
