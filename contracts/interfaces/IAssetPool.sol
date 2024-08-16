// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "./IBondingCurve.sol";

interface IAssetPool {
    event TransferredAsset(address indexed sender, address indexed recipient, address token, uint256 amount);
    event TransferredReserveAsset(address indexed sender, address indexed recipient, uint256 amount);

    function VERSION() external view returns (uint8);
    function INITIAL_TOKEN_SUPPLY() external view returns (uint256);
    function MAX_RESERVE_BALANCE() external view returns (uint256);
    function erc404TokenAddress() external view returns (address);
    function tradingHubAddress() external view returns (address);
    function bondingCurve() external view returns (IBondingCurve);

    function transferAsset(uint256 amount_, address recipient_) external;
    function transferReserveAsset(uint256 amount_, address recipient_) external;
    function sendAllAssetToLockedPool() external;
}
