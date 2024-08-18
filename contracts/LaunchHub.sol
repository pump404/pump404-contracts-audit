// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ILaunchHub.sol";
import "./interfaces/ITradingHub.sol";
import "./AssetPool.sol";
import "./ERC404Token.sol";

contract LaunchHub is ILaunchHub, Ownable {

    // launch fee
    uint256 public immutable launchFee;

    address public lockedPoolAddress;
    address public treasuryAddress;
    address public erc404Operator;

    ITradingHub public tradingHub;
    IBondingCurve public bondingCurve;

    mapping(address => uint256) private nonces;

    constructor(uint256 launchFee_) Ownable(msg.sender) {
        require(launchFee_ >= 0, "Launch: launch fee must be greater than or equal to 0");
        launchFee = launchFee_;
    }

    function setBondingCurve(address bondingCurveAddress_) external onlyOwner {
        require(bondingCurveAddress_ != address(0), "Launch: bonding curve address is the zero address");
        bondingCurve = IBondingCurve(bondingCurveAddress_);
    }

    function setLockedPoolAddress(address lockedPoolAddress_) external onlyOwner {
        require(lockedPoolAddress_ != address(0), "Launch: locked pool address is the zero address");
        lockedPoolAddress = lockedPoolAddress_;
    }

    function setTreasuryAddress(address treasuryAddress_) external onlyOwner {
        require(treasuryAddress_ != address(0), "Launch: treasury address is the zero address");
        treasuryAddress = treasuryAddress_;
    }

    function setERC404Operator(address erc404Operator_) external onlyOwner {
        require(erc404Operator_ != address(0), "Launch: erc404 operator is the zero address");
        erc404Operator = erc404Operator_;
    }

    function setTradingHub(address tradingHubAddress_) external onlyOwner {
        require(tradingHubAddress_ != address(0), "Launch: trading hub is the zero address");
        tradingHub = ITradingHub(tradingHubAddress_);
    }

    function launchErc404(string memory name_, string memory symbol_, string memory defaultBaseURI_,  uint256 initial_buy_amount_) external payable override {
        require(bytes(name_).length > 0, "Launch: name is empty");
        require(bytes(symbol_).length > 0, "Launch: symbol is empty");

        require(msg.value >= launchFee + initial_buy_amount_, "Launch: insufficient funds to launch");

        uint256 ratio = 100_000;
        bytes32 _salt = keccak256(abi.encodePacked(name_, symbol_, ratio, nonces[msg.sender]));

        ERC404Token erc404Token = new ERC404Token{salt: _salt}(name_, symbol_, defaultBaseURI_, 18, ratio, erc404Operator, address(tradingHub));

        AssetPool assetPool = new AssetPool(address(erc404Token), address(tradingHub), address(bondingCurve));

        erc404Token.mintForPools(address(assetPool), lockedPoolAddress);

        uint256 base_reserve = bondingCurve.INITIAL_RESERVE_BALANCE();

        bool success;
        require(msg.value >= base_reserve, "Launch: insufficient funds to transfer bonding curve base reserve");
        (success, ) = payable(address(assetPool)).call{value: base_reserve}("");
        if (!success) {
            revert("Launch: failed to transfer bonding curve reserve");
        }

        require(msg.value >= launchFee - base_reserve, "Launch: insufficient funds to transfer fee");
        (success, ) = payable(treasuryAddress).call{value: launchFee - base_reserve}("");
        if (!success) {
            revert("Launch: failed to transfer launch fee");
        }
        tradingHub.setTokenInAssetPool(address(erc404Token), address(assetPool));

        nonces[msg.sender] += 1;

        emit LaunchedERC404(address(assetPool), address(bondingCurve), address(erc404Token), msg.sender, initial_buy_amount_, erc404Operator);

        if (initial_buy_amount_ > 0) {
            require(msg.value == launchFee + initial_buy_amount_, "Launch: insufficient funds to buy initial amount");
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

