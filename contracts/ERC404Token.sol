// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC404U16} from "./dependencies/ERC404U16.sol";

contract ERC404Token is ERC404U16 {

    uint24 public constant TOTAL_ERC721_SUPPLY = 10000; 

    // this number will send to locked pool
    uint256 public immutable SEND_TO_LOCKED_POOL;

    string private _baseURI;

    address public launchHubAddress;
    address public tradingHubAddress;

    // operator can set the ERC721 token transfer exempt
    address public operator;

    event SetBaseURI(string baseURI);

    modifier onlyOperator() {
        require(msg.sender == operator || msg.sender == tradingHubAddress, "ERC404Token: caller is not the operator or trading hub");
        _;
    }

    modifier onlyLaunchHub() {
        require(msg.sender == launchHubAddress , "ERC404Token: caller is not the launch contract");
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        string memory defaultBaseURI_,
        uint8 decimals_,
        uint256 ratio_,
        address operator_,
        address tradingHubAddress_
    ) ERC404U16(name_, symbol_, decimals_, ratio_) {
        require(bytes(defaultBaseURI_).length > 0, "ERC404Token: baseURI is empty");
        _baseURI = defaultBaseURI_;

        launchHubAddress = msg.sender; // launch contract address

        require(operator_ != address(0), "ERC404Token: operator is the zero address");
        operator = operator_;

        require(tradingHubAddress_ != address(0), "ERC404Token: trading hub is the zero address");
        tradingHubAddress = tradingHubAddress_;

        SEND_TO_LOCKED_POOL = 210000000 ether; 
    }

    /**
    * @dev Mint ERC404 tokens for the asset pool and locked pool
    * @param assetPool_ address of the asset pool
    * @param lockedPool_ address of the locked pool
    */
    function mintForPools(address assetPool_, address lockedPool_) external onlyLaunchHub {
        _setERC721TransferExempt(assetPool_, true);
        _setERC721TransferExempt(lockedPool_, true);

        uint256 totalSupply = TOTAL_ERC721_SUPPLY * units;
        _mintERC20(assetPool_, totalSupply - SEND_TO_LOCKED_POOL);
        _mintERC20(lockedPool_, SEND_TO_LOCKED_POOL);
    }

    /**
    * @dev Retrun the URI for the tokenId
    * @param id_ the tokenId of Collection
    * @return the URI for the tokenId
    */
    function tokenURI(uint256 id_) public view override returns (string memory) {
        if (bytes(_baseURI).length == 0) {
            return "";
        }

        return string.concat(_baseURI, Strings.toString(id_));
    }

    /**
    * @dev Set the ERC721 token transfer exempt to prevent minting NFTs in frequent trading
    * @param account_ the address of the account
    * @param value_ setting or cancelling the exemption
    */
    function setERC721TransferExempt(address account_, bool value_) external onlyOperator {
        _setERC721TransferExempt(account_, value_);
    }

    /**
    * @dev Set the base URI for the tokens
    * @param baseURI_ the base URI for the tokens
    */
    function setBaseURI(string memory baseURI_) external onlyOperator {
        _baseURI = baseURI_;
        emit SetBaseURI(baseURI_);
    }
}
