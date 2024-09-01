// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ILaunchHub.sol";
import "./interfaces/ITradingHub.sol";
import "./AssetPool.sol";
import "./ERC404Token.sol";

contract LaunchHub is ILaunchHub, Ownable {

    // launch fee
    uint256 public launchFee;

    address public lockedPoolAddress;
    address public treasuryAddress;
    address public erc404Operator;

    ITradingHub public tradingHub;
    IBondingCurve public bondingCurve;

    mapping(address => uint256) private nonces;

    constructor() Ownable(msg.sender) {}

    function setBondingCurve(address bondingCurveAddress_) external onlyOwner {
        require(bondingCurveAddress_ != address(0), "LaunchHub: bonding curve address is the zero address");
        bondingCurve = IBondingCurve(bondingCurveAddress_);
        emit SetBondingCurve(bondingCurveAddress_);
    }

    function setLaunchFee(uint256 launchFee_) external onlyOwner {
        require(launchFee_ >= 0, "LaunchHub: launch fee must be greater than or equal to 0");
        require(address(bondingCurve) != address(0), "LaunchHub: bonding curve must be set before setting the launch fee");
        require(launchFee_ >= bondingCurve.INITIAL_RESERVE_BALANCE(), "LaunchHub: launch fee must be greater than or equal to the bonding curve base reserve");

        launchFee = launchFee_;
        emit SetLaunchFee(launchFee_);
    }

    function setLockedPoolAddress(address lockedPoolAddress_) external onlyOwner {
        require(lockedPoolAddress_ != address(0), "LaunchHub: locked pool address is the zero address");
        lockedPoolAddress = lockedPoolAddress_;
        emit SetLockedPoolAddress(lockedPoolAddress_);
    }

    function setTreasuryAddress(address treasuryAddress_) external onlyOwner {
        require(treasuryAddress_ != address(0), "LaunchHub: treasury address is the zero address");
        treasuryAddress = treasuryAddress_;
        emit SetTreasuryAddress(treasuryAddress_);
    }

    function setERC404Operator(address erc404Operator_) external onlyOwner {
        require(erc404Operator_ != address(0), "LaunchHub: erc404 operator is the zero address");
        erc404Operator = erc404Operator_;
        emit SetERC404Operator(erc404Operator_);
    }

    function setTradingHub(address tradingHubAddress_) external onlyOwner {
        require(tradingHubAddress_ != address(0), "LaunchHub: trading hub is the zero address");
        tradingHub = ITradingHub(tradingHubAddress_);
        emit SetTradingHub(tradingHubAddress_);
    }

    function launchErc404(string memory name_, string memory symbol_, string memory defaultBaseURI_,  uint256 initial_buy_amount_) external payable override {
        require(launchFee >= 0 && address(bondingCurve) != address(0) && lockedPoolAddress != address(0) && treasuryAddress != address(0) && erc404Operator != address(0) && address(tradingHub) != address(0), "LaunchHub: initialization not complete");

        require(bytes(name_).length > 0, "LaunchHub: name is empty");
        require(bytes(symbol_).length > 0, "LaunchHub: symbol is empty");

        require(msg.value >= launchFee + initial_buy_amount_, "LaunchHub: insufficient funds to launch");

        uint256 ratio = 100_000;
        bytes32 _salt = keccak256(abi.encodePacked(name_, symbol_, ratio, nonces[msg.sender]));

        ERC404Token erc404Token = new ERC404Token{salt: _salt}(name_, symbol_, defaultBaseURI_, 18, ratio, erc404Operator, address(tradingHub));

        AssetPool assetPool = new AssetPool(address(erc404Token), address(tradingHub), address(bondingCurve));

        erc404Token.mintForPools(address(assetPool), lockedPoolAddress);

        uint256 base_reserve = bondingCurve.INITIAL_RESERVE_BALANCE();

        bool success;
        require(msg.value >= base_reserve, "LaunchHub: insufficient funds to transfer bonding curve base reserve");
        (success, ) = payable(address(assetPool)).call{value: base_reserve}("");
        if (!success) {
            revert("LaunchHub: failed to transfer bonding curve reserve");
        }

        require(msg.value >= launchFee - base_reserve, "LaunchHub: insufficient funds to transfer fee");
        (success, ) = payable(treasuryAddress).call{value: launchFee - base_reserve}("");
        if (!success) {
            revert("LaunchHub: failed to transfer launch fee");
        }
        tradingHub.setTokenInAssetPool(address(erc404Token), address(assetPool));

        nonces[msg.sender] += 1;

        emit LaunchedERC404(address(assetPool), address(bondingCurve), address(erc404Token), msg.sender, initial_buy_amount_, erc404Operator);

        if (initial_buy_amount_ > 0) {
            require(msg.value == launchFee + initial_buy_amount_, "LaunchHub: insufficient funds to buy initial amount");
            if (erc404Token.erc721TransferExempt(msg.sender)) {
                erc404Token.setERC721TransferExempt(msg.sender, false);
            }
            ITradingHub.InputData memory input_data = ITradingHub.InputData({
            tokenIn: address(0),
            tokenOut: address(erc404Token),
            recipient: msg.sender,
            amountIn: initial_buy_amount_,
            amountOutMinimum: 0
        });
            tradingHub.swap{value: initial_buy_amount_}(input_data);
        }
    }
}

