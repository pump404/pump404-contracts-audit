// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import "./dependencies/uniswapV3/ISwapRouter02.sol";
import "./interfaces/IWETH9.sol";
import "./interfaces/IUniswapV3NonfungiblePositionManager.sol";
import "./interfaces/IUniswapV3.sol";
import "./interfaces/IERC404.sol";
import "./interfaces/ITradingHub.sol";

contract UniswapV3 is IUniswapV3, Initializable, UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {

    ISwapRouter02 private swapRouter;
    IUniswapV3NonfungiblePositionManager private nonfungiblePositionManager;
    IQuoterV2 private quoterV2;
    ITradingHub public tradingHub;

    address public treasury_address;
    uint24 public trading_fee_rate;
    uint24 public constant denominator = 10000;

    function initialize(address swap_router_address_, address nonfungiable_position_manager_address_, address quoter_v2_address_, address trading_hub_address_) public initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();

        require(swap_router_address_ != address(0), 'UniswapV3: swap_router_address is the zero address');
        swapRouter = ISwapRouter02(swap_router_address_);

        require(nonfungiable_position_manager_address_ != address(0), 'UniswapV3: nonfungiable_position_manager_address is the zero address');
        nonfungiblePositionManager = IUniswapV3NonfungiblePositionManager(nonfungiable_position_manager_address_);

        require(quoter_v2_address_ != address(0), 'UniswapV3: quoter_v2_address is the zero address');
        quoterV2 = IQuoterV2(quoter_v2_address_);

        require(trading_hub_address_ != address(0), 'UniswapV3: trading_hub_address is the zero address');
        tradingHub = ITradingHub(trading_hub_address_);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setTradingFeeRate(uint24 trading_fee_rate_) public onlyOwner {
        require(trading_fee_rate_ < denominator, 'UniswapV3: trading_fee_rate must be less than denominator');
        trading_fee_rate = trading_fee_rate_;

        emit TradingFeeRateChanged(trading_fee_rate);
    }

    function setTreasuryAddress(address treasury_address_) public onlyOwner {
        require(treasury_address_ != address(0), 'UniswapV3: treasury_address is the zero address');
        treasury_address = treasury_address_;

        emit TreasuryAddressChanged(treasury_address_);
    }

    /**
    * @dev Swap tokens through uniswap v3
    * @notice The token is only swapped with ETH
    * @param from_token_address The token to swap
    * @param to_token_address The token to receive
    * @param in_amount The amount of token to swap
    * @param out_amount_min The minimum amount of token to receive
    */
    function swap(address from_token_address, address to_token_address, uint256 in_amount, uint256 out_amount_min) external payable override nonReentrant whenNotPaused {
        require(from_token_address != to_token_address, 'UniswapV3: from_token_address and to_token_address cannot be the same');

        address weth_address = nonfungiblePositionManager.WETH9();

        IERC404 erc404;
        if (from_token_address == address(0)) {
            from_token_address = weth_address;
            erc404 = IERC404(to_token_address);
        } else {
            to_token_address = weth_address;
            erc404 = IERC404(from_token_address);
        }

        if (from_token_address == weth_address) {
            require(msg.value == in_amount, 'UniswapV3: msg.value is not equal to in_amount');
        }

        if (!erc404.erc721TransferExempt(msg.sender) && erc404.erc721BalanceOf(msg.sender) == 0 ) {
            tradingHub.setUserToErc404Exempt(address(erc404), msg.sender, true);
        }

        address to_user_address = msg.sender;

        address recipient = to_user_address;
        uint256 trading_amount = in_amount;
        uint256 trading_fee = 0;

        if (from_token_address != weth_address) {
            // sell token to ETH
            IERC20 from_token = IERC20(from_token_address);
            require(from_token.allowance(msg.sender, address(this)) >= in_amount, 'UniswapV3: from_token allowance is insufficient funds');
            require(from_token.balanceOf(msg.sender) >= in_amount, 'UniswapV3: from_token balance is insufficient funds');

            from_token.transferFrom(msg.sender, address(this), in_amount);

            if (from_token.allowance(address(this), address(swapRouter)) < in_amount) {
                from_token.approve(address(swapRouter), type(uint256).max);
            }
            recipient = address(this);
        } else {
            // buy token with ETH
            trading_fee = in_amount * trading_fee_rate / denominator;
            require(in_amount > trading_fee, 'UniswapV3: in_amount is less than trading_fee');
            trading_amount = in_amount - trading_fee;
            if (trading_fee > 0) {
                (bool success, ) = treasury_address.call{value: trading_fee}('');
                require(success, 'UniswapV3: transfer to treasury_address failed');
            }
        }

        (, uint24 fee) = getPool(from_token_address, to_token_address);

        // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
        // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
        ISwapRouter02.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
            tokenIn : from_token_address,
            tokenOut : to_token_address,
            fee : fee,
            recipient : recipient,
            amountIn : trading_amount,
            amountOutMinimum : out_amount_min,
            sqrtPriceLimitX96 : 0
        });

        uint256 out_amount = 0;
//        IERC20 token;
        // The call to `exactInputSingle` executes the swap.
        if (from_token_address == weth_address) {
            out_amount = swapRouter.exactInputSingle{value: trading_amount}(params);

            // refund leftover ETH to user
//            if (address(this).balance > 0) {
//                (bool success, ) = msg.sender.call{value: address(this).balance}('');
//                require(success, 'UniswapV3: refund to msg.sender failed');
//            }
//            token = IERC20(to_token_address);
        } else {
            out_amount = swapRouter.exactInputSingle(params);

            if (recipient == address(this)) {
                IWETH9 weth = IWETH9(weth_address);

                require(weth.balanceOf(address(this)) >= out_amount, 'UniswapV3: insufficient weth balance');
                weth.withdraw(out_amount);

                require(address(this).balance >= out_amount, 'UniswapV3: insufficient weth balance');
                trading_fee = out_amount * trading_fee_rate / denominator;
                require(out_amount > trading_fee, 'UniswapV3: in_amount is less than trading_fee');
                trading_amount = out_amount - trading_fee;

                bool success;
                if (trading_fee > 0) {
                    (success, ) = treasury_address.call{value: trading_fee}('');
                    require(success, 'UniswapV3: transfer to treasury_address failed');
                }

                (success, ) = to_user_address.call{value: trading_amount}('');
                require(success, 'UniswapV3: transfer to to_user_address failed');
            }
//            token = IERC20(from_token_address);
        }

        // refund leftover token to user
//        if (token.balanceOf(address(this)) > 0) {
//            token.transfer(msg.sender, token.balanceOf(address(this)));
//        }

        emit Swapped(from_token_address, to_token_address, to_user_address, in_amount, out_amount, trading_fee);
    }

    /**
    * @dev Get the LP pool address and fee
    * @param token0_address The token0 address
    * @param token1_address The token1 address
    * @return pool The LP pool address
    */
    function getPool(address token0_address, address token1_address) public view override returns (address, uint24) {
        address pool;
//        uint24 _poolFee500 = 500;
//        uint24 _poolFee3000 = 3000;
        uint24 _poolFee10000 = 10000;

        /*       uint24 fee = _poolFee500;
               pool = _getPool(token0_address, token1_address, _poolFee500);
               if (pool == address(0)) {
                   pool = _getPool(token0_address, token1_address, _poolFee3000);
                   fee = _poolFee3000;
               }
               if (pool == address(0)) {
                   pool = _getPool(token0_address, token1_address, _poolFee10000);
                   fee = _poolFee10000;
               }*/
        pool = _getPool(token0_address, token1_address, _poolFee10000);
        uint24 fee = _poolFee10000;
        require(pool != address(0), 'UniswapV3: LP pool is not existed');

        return (pool, fee);
    }

    function _getPool(address token0_address, address token1_address, uint24 fee) private view returns (address) {
        IUniswapV3Factory factory = IUniswapV3Factory(nonfungiblePositionManager.factory());
        address pool;

        require(fee > 0, 'UniswapV3: fee must be greater than 0');

//        (token0_address, token1_address) = token0_address < token1_address ? (token0_address, token1_address) : (token1_address, token0_address);
        pool = factory.getPool(token0_address, token1_address, fee);

        if (pool == address(0)) {
            pool = factory.getPool(token1_address, token0_address, fee);
        }
        return pool;
    }

    /**
    * @dev Get the amount of InToken required to exchange OutToken
    * @param in_token_address The token to be exchanged
    * @param out_token_address The token to be exchanged
    * @param in_amount The amount of token to be exchanged
    */
    function getOutTokenAmountFromInTokenAmount(address in_token_address, address out_token_address, uint256 in_amount) external override {
        address weth_address = nonfungiblePositionManager.WETH9();
        if (in_token_address == address(0)) {
            in_token_address = weth_address;
        } else {
            out_token_address = weth_address;
        }
        uint160 sqrtPriceLimitX96 = 0;

        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn : in_token_address,
            tokenOut : out_token_address,
            fee : 10000,
            amountIn : in_amount,
            sqrtPriceLimitX96 : sqrtPriceLimitX96
        });
        (uint256 out_amount, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate)
        = quoterV2.quoteExactInputSingle(params);

        // 通过 revert 抛出错误并附加结果数据
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, out_amount)
            mstore(add(ptr, 0x20), sqrtPriceX96After)
            mstore(add(ptr, 0x40), initializedTicksCrossed)
            mstore(add(ptr, 0x60), gasEstimate)
            revert(ptr, 128) // 4 * 32 bytes
        }
    }

    receive() external payable {
    }
}
