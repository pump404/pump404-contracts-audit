// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "./ITradingHub.sol";

interface ILaunchHub {

    event SetLaunchFee(uint256 launch_fee);
    event SetBondingCurve(address indexed bonding_curve);
    event SetLockedPoolAddress(address indexed locked_pool_address);
    event SetTreasuryAddress(address indexed treasury_address);
    event SetERC404Operator(address indexed erc404_operator);
    event SetTradingHub(address indexed trading_hub);

    event LaunchedERC404(address indexed asset_pool, address bonding_curve, address erc404_token, address creator, uint256 initial_buy_amount, address operator);

    function launchFee() external view returns (uint256);
    function lockedPoolAddress() external view returns (address);
    function treasuryAddress() external view returns (address);
    function erc404Operator() external view returns (address);

    function tradingHub() external view returns (ITradingHub);

    function launchErc404(string memory name_, string memory symbol_, string memory defaultBaseURI_, uint256 initial_buy_amount_) external payable;
}
