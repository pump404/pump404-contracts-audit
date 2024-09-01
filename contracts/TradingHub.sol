// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ITradingHub.sol";
import "./interfaces/IAssetPool.sol";
import "./interfaces/IBondingCurve.sol";
import "./interfaces/ILockedAssetPool.sol";
import "./interfaces/IERC404.sol";

contract TradingHub is ITradingHub, Initializable, UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {

    uint8 public constant VERSION = 1;

    // charge fee in trading
    uint32 public tradingFeeRate;

    uint32 public constant DENOMINATOR = 10000;

    address public treasuryAddress;

    address public launchHubAddress;

    mapping(address => address) public tokenInAssetPool;

    // minimum eth to buy
    uint256 public constant MINIMUM_ETH_BUY = 10**13;

    address public lockedAssetPoolAddress;

    address public operator;

    modifier onlyLaunchHub() {
        require(msg.sender == launchHubAddress, "TradingHub: caller is not the launch contract");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "TradingHub: caller is not the operator");
        _;
    }

    function initialize(uint32 tradingFeeRate_) public initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();

        require(tradingFeeRate_ > 0, "TradingHub: trading fee is 0");
        tradingFeeRate = tradingFeeRate_;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setLaunchHubAddress(address launchHubAddress_) external onlyOwner {
        require(launchHubAddress_ != address(0), "TradingHub: launch hub address is the zero address");
        launchHubAddress = launchHubAddress_;
    }

    function setTreasuryAddress(address treasuryAddress_) external onlyOwner {
        require(treasuryAddress_ != address(0), "TradingHub: treasury address is the zero address");
        treasuryAddress = treasuryAddress_;
    }

    function setTradingFeeRate(uint32 tradingFeeRate_) external onlyOwner {
        require(tradingFeeRate_ > 0, "TradingHub: trading fee is 0");
        require(tradingFeeRate_ != tradingFeeRate, "TradingHub: trading fee is the same");
        tradingFeeRate = tradingFeeRate_;
    }

    /**
    * @dev Set the locked asset pool address
    * @param lockedAssetPoolAddress_ address of the locked asset pool
    */
    function setLockedAssetPoolAddress(address lockedAssetPoolAddress_) external onlyOwner {
        require(lockedAssetPoolAddress_ != address(0), "TradingHub: locked asset pool address is the zero address");
        lockedAssetPoolAddress = lockedAssetPoolAddress_;
    }

    function setOperator(address operator_) external onlyOwner {
        require(operator_ != address(0), "TradingHub: operator address is the zero address");
        operator = operator_;
    }

    /**
    * @dev Set the relationship between asset pool and token address
    * @param token_ address of the token
    * @param assetPool_ address of the asset pool
    */
    function setTokenInAssetPool(address token_, address assetPool_) external override onlyLaunchHub {
        require(token_ != address(0), "TradingHub: token address is the zero address");
        require(assetPool_ != address(0), "TradingHub: asset pool address is the zero address");

        tokenInAssetPool[token_] = assetPool_;
    }

    /**
    * @dev Calculate the amount of token to buy
    * @param tokenAddress_ address of the token
    * @param ethAmount_ amount of eth
    * @return amount of token
    */
    function calculatePurchaseReturn(address tokenAddress_, uint256 ethAmount_) public view override returns(uint256) {
        require(tokenAddress_ != address(0), "TradingHub: token address is the zero address");
        require(tokenInAssetPool[tokenAddress_] != address(0), "TradingHub: asset pool address is the zero address");

        IAssetPool asset_pool = IAssetPool(tokenInAssetPool[tokenAddress_]);

        IBondingCurve bonding_curve = asset_pool.bondingCurve();

        uint256 token_supply = asset_pool.INITIAL_TOKEN_SUPPLY() - IERC20(tokenAddress_).balanceOf(address(asset_pool)) + bonding_curve.INITIAL_TOKEN_BALANCE();
        uint256 connector_balance = address(asset_pool).balance;

        // deduct the trading fee
        uint256 deposite_amount = ethAmount_; //  - ethAmount_ * tradingFeeRate / DENOMINATOR;
        uint32 connector_weight = bonding_curve.CURVE_WEIGHT();
        return bonding_curve.calculatePurchaseReturn(token_supply, connector_balance, connector_weight, deposite_amount);
    }

    /**
    * @dev Calculate the amount of eth to sell
    * @param tokenAddress_ address of the token
    * @param tokenAmount_ amount of token
    * @return amount of eth
    */
    function calculateSaleReturn(address tokenAddress_, uint256 tokenAmount_) public view override returns(uint256) {
        require(tokenAddress_ != address(0), "TradingHub: token address is the zero address");
        require(tokenInAssetPool[tokenAddress_] != address(0), "TradingHub: asset pool address is the zero address");

        IAssetPool asset_pool = IAssetPool(tokenInAssetPool[tokenAddress_]);

        IBondingCurve bonding_curve = asset_pool.bondingCurve();

        uint256 token_supply = asset_pool.INITIAL_TOKEN_SUPPLY() - IERC20(tokenAddress_).balanceOf(address(asset_pool)) + bonding_curve.INITIAL_TOKEN_BALANCE();
        uint256 connector_balance = address(asset_pool).balance;
        uint256 sell_amount = tokenAmount_;
        uint32 connector_weight = bonding_curve.CURVE_WEIGHT();

        uint256 eth_amount_out = bonding_curve.calculateSaleReturn(token_supply, connector_balance, connector_weight, sell_amount);
        // need to deduct the trading fee
        return eth_amount_out; // - eth_amount_out * tradingFeeRate / DENOMINATOR;
    }

    /**
    * @dev Swap eth to token or token to eth
    * @param inputData_ input data
    */
    function swap(InputData calldata inputData_) external payable override nonReentrant whenNotPaused {
        require(inputData_.amountIn > 0, "TradingHub: amount in must be greater than 0");
        require(inputData_.tokenIn != inputData_.tokenOut, "TradingHub: token in and token out cannot be the same");

        address token_address;
        bool is_buy = false;
        if (inputData_.tokenIn == address(0)) {
            is_buy = true;
            token_address = inputData_.tokenOut;
        } else if (inputData_.tokenOut == address(0)) {
            token_address = inputData_.tokenIn;
        } else {
            revert("TradingHub: token in or token out must be a token");
        }

        require(tokenInAssetPool[token_address] != address(0), "TradingHub: asset pool address is not existed");

        IAssetPool asset_pool = IAssetPool(tokenInAssetPool[token_address]);

        IERC404 erc404 = IERC404(token_address);

        if (!erc404.erc721TransferExempt(inputData_.recipient) && erc404.erc721BalanceOf(inputData_.recipient) == 0) {
            erc404.setERC721TransferExempt(inputData_.recipient, true);
        }

        IERC20 token = IERC20(token_address);

        bool success;

        if (is_buy) {
            require(msg.value == inputData_.amountIn, "TradingHub: eth value is not equal to amount in");
            require(msg.value >= MINIMUM_ETH_BUY, "TradingHub: eth amount is less than minimum eth to buy");

            uint256 treasury_fee = (inputData_.amountIn * tradingFeeRate) / DENOMINATOR;
            uint256 transfer_amount = inputData_.amountIn - treasury_fee;

            uint256 token_amount_out = calculatePurchaseReturn(token_address, transfer_amount);

            uint256 token_balance_in_pool = token.balanceOf(address(asset_pool));

            require(token_balance_in_pool >= token_amount_out, "TradingHub: insufficient token balance in asset pool");
            require(token_amount_out >= inputData_.amountOutMinimum, "TradingHub: the slippery may be too low");


            (success, ) = address(asset_pool).call{value: transfer_amount}("");
            require(success, "TradingHub: failed to transfer eth to asset pool");

            (success, ) = treasuryAddress.call{value: treasury_fee}("");
            require(success, "TradingHub: failed to transfer eth to treasury");

            asset_pool.transferAsset(token_amount_out, inputData_.recipient);

            emit BoughtToken(inputData_.recipient, token_address, token_amount_out, inputData_.amountIn);
        } else {
            uint256 transfer_token_amount = inputData_.amountIn;
            require(token.allowance(msg.sender, address(this)) >= transfer_token_amount, "TradingHub: insufficient token allowance");
            require(token.balanceOf(msg.sender) >= transfer_token_amount, "TradingHub: insufficient token balance to sell");

            uint256 eth_amount_out = calculateSaleReturn(token_address, transfer_token_amount);
            require(eth_amount_out >= inputData_.amountOutMinimum, "TradingHub: the slippery may be too low");
            require(eth_amount_out >= MINIMUM_ETH_BUY, "TradingHub: eth amount out is less than minimum eth buy");

            uint256 eth_balance_in_pool = address(asset_pool).balance;
            require(eth_balance_in_pool >= eth_amount_out, "TradingHub: insufficient eth balance");

            uint256 treasury_fee = (eth_amount_out * tradingFeeRate) / DENOMINATOR;
            uint256 transfer_amount = eth_amount_out - treasury_fee;

            asset_pool.transferReserveAsset(transfer_amount, inputData_.recipient);
            asset_pool.transferReserveAsset(treasury_fee, treasuryAddress);

            token.transferFrom(msg.sender, address(asset_pool), transfer_token_amount);

            emit SoldToken(msg.sender, token_address, transfer_token_amount, transfer_amount);
        }
    }


    /**
    * @dev Import all ERC404s to Uniswap V3
    */
    function sendToUniswapV3(address tokenAddress_, uint160 sqrtPriceX96_, int24 tickLower, int24 tickUpper) external override onlyOperator {
        IAssetPool assetPool = IAssetPool(tokenInAssetPool[tokenAddress_]);
        require(address(assetPool).balance >= assetPool.MAX_RESERVE_BALANCE(), "TradingHub: asset pool is not reach the max reserve balance");

        assetPool.sendAllAssetToLockedPool();

        ILockedAssetPool lockedAssetPool = ILockedAssetPool(lockedAssetPoolAddress);

        (uint256 tokenId, uint128 liquidity, address v3_pool, uint256 amount0, uint256 amount1, uint256 ignition_fee)
        = lockedAssetPool.sendToUniswapV3(tokenAddress_, sqrtPriceX96_, tickLower, tickUpper);

        emit SentToUniswapV3(tokenAddress_, v3_pool, tokenId, liquidity, amount0, amount1, ignition_fee);
    }
}
