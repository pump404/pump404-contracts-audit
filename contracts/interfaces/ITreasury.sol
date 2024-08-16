// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITreasury {

    event Deposited(address indexed sender, uint256 indexed value);
    event Withdrew(address indexed recipient, uint256 indexed value);

    function withdraw(address recipient_, uint256 value_) external;

}
