// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {ITreasury} from './interfaces/ITreasury.sol';


contract Treasury is ITreasury, Initializable, UUPSUpgradeable, OwnableUpgradeable {

    // token address or address => total fee
    mapping(address => uint256) public contributionValue;

    function initialize() public initializer {
        __Ownable_init(msg.sender);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function withdraw(address recipient_, uint256 value_) external onlyOwner {
        require(recipient_ != address(0), "Treasury: recipient is the zero address");
        require(value_ > 0, "Treasury: value must be greater than 0");
        require(address(this).balance >= value_, "Treasury: insufficient eth balance");

        (bool success, ) = recipient_.call{value: value_}("");
        require(success, "Treasury: failed to transfer eth to recipient");

        emit Withdrew(recipient_, value_);
    }

    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }
}
