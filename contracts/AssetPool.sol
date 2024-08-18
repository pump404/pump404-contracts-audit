// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IAssetPool.sol";
import "./interfaces/IBondingCurve.sol";
import "./interfaces/IERC404.sol";
import "./interfaces/ITradingHub.sol";

contract AssetPool is IAssetPool{

    uint8 public constant VERSION = 1;

    bool public ignited = false;

    uint256 public constant INITIAL_TOKEN_SUPPLY = 336_000_000 * 10**18;

    uint256 public constant MAX_RESERVE_BALANCE = 38 * 10**17;

    address public erc404TokenAddress;

    address public tradingHubAddress;

    IBondingCurve public bondingCurve;

    modifier onlyTradingHub() {
        require(msg.sender == tradingHubAddress, "AssetPool: caller is not the trading hub");
        _;
    }

    constructor(address tokenAddress_, address tradingHubAddress_, address bondingCurveAddress_) {
        require(tokenAddress_ != address(0), "AssetPool: token address is the zero address");
        erc404TokenAddress = tokenAddress_;

        require(tradingHubAddress_ != address(0), "AssetPool: market address is the zero address");
        tradingHubAddress = tradingHubAddress_;

        require(bondingCurveAddress_ != address(0), "AssetPool: bonding curve address is the zero address");
        bondingCurve = IBondingCurve(bondingCurveAddress_);
    }

    /**
    * @dev Transfer asset to recipient
    * @param amount_ amount of asset to transfer
    * @param recipient_ recipient address
    */
    function transferAsset(uint256 amount_, address recipient_) external onlyTradingHub {
        require(amount_ > 0, "AssetPool: amount must be greater than 0");
        require(recipient_ != address(0), "AssetPool: recipient address is the zero address");

        _checkStatus();

        IERC20 token = IERC20(erc404TokenAddress);
        require(token.balanceOf(address(this)) >= amount_, "AssetPool: insufficient token balance");

        token.transferFrom(address(this), recipient_, amount_);

        emit TransferredAsset(address(this), recipient_, address(token), amount_);
    }

    /**
    * @dev Transfer reserve asset to recipient
    * @param amount_ amount of reserve asset to transfer
    * @param recipient_ recipient address
    */
    function transferReserveAsset(uint256 amount_, address recipient_) external override onlyTradingHub {
        _checkStatus();

        require(amount_ > 0, "AssetPool: amount must be greater than 0");
        require(recipient_ != address(0), "AssetPool: recipient address is the zero address");

        require(address(this).balance >= amount_, "AssetPool: insufficient reserve balance");

        (bool success, ) = recipient_.call{value: amount_}("");
        require(success, "AssetPool: failed to transfer reserve asset");

        emit TransferredReserveAsset(address(this), recipient_, amount_);
    }

    /**
    * @dev Send remaining asset to locked pool for igniting
    */
    function sendAllAssetToLockedPool() external override onlyTradingHub {
        require(!ignited, "AssetPool: the pool has already been ignited");
//        require(IERC20(erc404TokenAddress).balanceOf(address(this)) <= 10**16, "AssetPool: token balance must be less than or equal to 0.01");

        address locked_asset_pool_address = ITradingHub(tradingHubAddress).lockedAssetPoolAddress();

        IERC20 token = IERC20(erc404TokenAddress);
        uint256 token_balance = token.balanceOf(address(this));
        if (token_balance > 0) {
            token.transferFrom(address(this), locked_asset_pool_address, token_balance);
        }

        (bool success, ) = locked_asset_pool_address.call{value: address(this).balance}("");
        require(success, "AssetPool: failed to transfer eth to locked pool");

        ignited = true;
    }

    function _checkStatus() internal view returns (bool) {
        require(IERC404(erc404TokenAddress).erc721TransferExempt(address(this)), "AssetPool: you must set the exempt before transferring");

        require(!ignited, "AssetPool: the pool has already been ignited");

        return true;
    }

    receive() external payable {}
}
