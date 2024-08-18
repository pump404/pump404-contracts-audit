// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILockedAssetPool.sol";
import "./interfaces/IUniswapV3NonfungiblePositionManager.sol";
import "./interfaces/ITradingHub.sol";
import "./interfaces/IAssetPool.sol";
import "./interfaces/IWETH9.sol";

contract LockedAssetPool is ILockedAssetPool, Initializable, UUPSUpgradeable, OwnableUpgradeable {

    address public launchHubAddress;

    IUniswapV3NonfungiblePositionManager public nonfungiblePositionManager;

    ITradingHub public tradingHub;
    // ignition fee
    uint256 public ignitionFee;

    modifier onlyTradingHub() {
        require(msg.sender == address(tradingHub), "LockedAssetPool: caller is not the trading hub");
        _;
    }

    function initialize() public initializer {
        __Ownable_init(msg.sender);
    }

    function setTradingHub(address tradingHubAddress_) external onlyOwner {
        require(tradingHubAddress_ != address(0), "LockedAssetPool: trading hub is the zero address");
        tradingHub = ITradingHub(tradingHubAddress_);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setUniswapV3NonfungiblePositionManager(address nonfungiblePositionManager_) external onlyOwner {
        require(nonfungiblePositionManager_ != address(0), "Launch: nonfungible position manager is the zero address");
        nonfungiblePositionManager = IUniswapV3NonfungiblePositionManager(nonfungiblePositionManager_);
    }

    function setIgnitionFee(uint256 ignitionFee_) external onlyOwner {
        require(ignitionFee_ >= 0, "LockedAssetPool: ignition fee must be greater than or equal to 0");
        ignitionFee = ignitionFee_;
    }

    function getAssetBalance(address asset_) external view returns (uint256) {
        IERC20 asset = IERC20(asset_);

        return asset.balanceOf(address(this));
    }

    /**
    * @dev Import all ERC404s to Uniswap V3
    * @notice price is around 0.000000044,
    * @notice the reserve is around 4.8 ETH
    */
    function sendToUniswapV3(address tokenAddress_, uint160 sqrtPriceX96_, int24 tickLower, int24 tickUpper) external onlyTradingHub returns(uint256 tokenId, uint128 liquidity, address v3_pool, uint256 amount0, uint256 amount1, uint256 ignition_fee) {
        require(address(nonfungiblePositionManager) != address(0), "Launch: nonfungible position manager is not be set");

        IAssetPool asset_pool = IAssetPool(tradingHub.tokenInAssetPool(tokenAddress_));
        require(address(asset_pool) != address(0), "LockedAssetPool: asset pool is not exist");

        uint256 eth_balance = address(this).balance;
        require(eth_balance >= asset_pool.MAX_RESERVE_BALANCE(), "LockedAssetPool: asset pool is not reach the max reserve balance");

        uint256 send_to_uniswap = asset_pool.MAX_RESERVE_BALANCE() - ignitionFee;

        IERC20 token = IERC20(tokenAddress_);
        IWETH9 weth = IWETH9(nonfungiblePositionManager.WETH9());

        uint256 token_balance = token.balanceOf(address(this));
        require(token_balance > 0, "LockedAssetPool: igniting token balance is zero");

        uint24 uniswap_fee = 10000;

        address token0 = tokenAddress_;
        address token1 = address(weth);
        uint256 token0_amount = token_balance;
        uint256 token1_amount = send_to_uniswap;
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
            (token0_amount, token1_amount) = (token1_amount, token0_amount);
        }

        v3_pool = nonfungiblePositionManager.createAndInitializePoolIfNecessary(token0, token1, uniswap_fee, sqrtPriceX96_);

        token.approve(address(nonfungiblePositionManager), type(uint256).max);

        IUniswapV3NonfungiblePositionManager.MintParams memory mintParams = IUniswapV3NonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: uniswap_fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: token0_amount,
            amount1Desired: token1_amount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: 0x000000000000000000000000000000000000dEaD, // abandoned the LP token
            deadline: block.timestamp
        });

        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint{value: send_to_uniswap}(mintParams);

        ignition_fee = eth_balance - send_to_uniswap;
        (bool success, ) = tradingHub.treasuryAddress().call{value: ignition_fee}("");
        require(success, "LockedAssetPool: failed to transfer ignition fee to treasury");
    }

    receive() external payable {}
}
