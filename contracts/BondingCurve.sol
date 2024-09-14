// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Power} from "./dependencies/Power.sol";
import {IBondingCurve} from "./interfaces/IBondingCurve.sol";

contract BondingCurve is IBondingCurve, Power {

    // v1
    uint256 public immutable INITIAL_TOKEN_BALANCE = 220_000 * 1e18;
    uint256 public immutable INITIAL_RESERVE_BALANCE = 1e13;
    uint32 public immutable CURVE_WEIGHT = 570_300; // 570_000;
    uint32 private immutable MAX_WEIGHT = 1000000;

    // v2
    uint256 public immutable VIRTUAL_ETH_RESERVE = 1.8 ether; // virtual ETH reserve, x0
    uint256 public immutable VIRTUAL_TOKEN_SUPPLY = 1_073_000_190.09 ether; // virtual total supply of token, y0
    uint256 public immutable K = VIRTUAL_ETH_RESERVE * VIRTUAL_TOKEN_SUPPLY; // 1931400343.8 ether;
    uint256 public immutable INITIAL_TOKEN_SUPPLY = 1_000_000_000 ether; // total supply of token
    uint256 public immutable VIRTUAL_TOKEN_LOCKED = VIRTUAL_TOKEN_SUPPLY - INITIAL_TOKEN_SUPPLY; // virtual token locked
    uint256 public immutable PRICE_PRECISION = 1e18;
    uint8 public override VERSION = 2;

     /** v1
     * @dev given a token supply, connector balance, weight and a deposit amount (in the connector token),
     * calculates the return for a given conversion (in the main token)
     *
     * Formula:
     * Return = _supply * ((1 + _depositAmount / _connectorBalance) ^ (_connectorWeight / 1000000) - 1)
     *
     * @param _supply              token total supply
     * @param _connectorBalance    total connector balance
     * @param _connectorWeight     connector weight, represented in ppm, 1-1000000
     * @param _depositAmount       deposit amount, in connector token
     *
     *  @return purchase return amount
     */
    function calculatePurchaseReturn(
        uint256 _supply,
        uint256 _connectorBalance,
        uint32 _connectorWeight,
        uint256 _depositAmount
    ) external view override returns (uint256) {
        // validate input
        require(_supply > 0 && _connectorBalance > 0 && _connectorWeight > 0 && _connectorWeight <= MAX_WEIGHT, "Invalid input[1]");
        // special case for 0 deposit amount
        if (_depositAmount == 0) {
            return 0;
        }
        // special case if the weight = 100%
        if (_connectorWeight == MAX_WEIGHT) {
            return (_supply * _depositAmount) / (_connectorBalance);
        }
        uint256 result;
        uint8 precision;
        uint256 baseN = _depositAmount + _connectorBalance;
        (result, precision) = power(baseN, _connectorBalance, _connectorWeight, MAX_WEIGHT);
        uint256 newTokenSupply = (_supply * result) >> precision;
        return newTokenSupply - _supply;
    }

    /** v1
     * @dev given a token supply, connector balance, weight and a sell amount (in the main token),
     * calculates the return for a given conversion (in the connector token)
     *
     * Formula:
     * Return = _connectorBalance * (1 - (1 - _sellAmount / _supply) ^ (1 / (_connectorWeight / 1000000)))
     *
     * @param _supply              token total supply
     * @param _connectorBalance    total connector
     * @param _connectorWeight     constant connector Weight, represented in ppm, 1-1000000
     * @param _sellAmount          sell amount, in the token itself
     *
     * @return sale return amount
     */

    function calculateSaleReturn(
        uint256 _supply,
        uint256 _connectorBalance,
        uint32 _connectorWeight,
        uint256 _sellAmount
    ) external view override returns (uint256) {
        // validate input
        require(
            _supply > 0 && _connectorBalance > 0 && _connectorWeight > 0 && _connectorWeight <= MAX_WEIGHT
            && _sellAmount <= _supply, "Invalid input[2]"
        );
        // special case for 0 sell amount
        if (_sellAmount == 0) {
            return 0;
        }
        // special case for selling the entire supply
        if (_sellAmount == _supply) {
            return _connectorBalance;
        }
        // special case if the weight = 100%
        if (_connectorWeight == MAX_WEIGHT) {
            return (_connectorBalance * _sellAmount) / _supply;
        }
        uint256 result;
        uint8 precision;
        uint256 baseD = _supply - _sellAmount;
        (result, precision) = power(_supply, baseD, MAX_WEIGHT, _connectorWeight);
        uint256 oldBalance = _connectorBalance * result;
        uint256 newBalance = _connectorBalance << precision;
        return (oldBalance - newBalance) / result;
    }
    
    /** v2
     * @dev Calculate the amount of tokens that can be purchased with a specified amount of ETH
     * @param ethReserve_  ETH balance in the asset pool
     * @param tokenReserve_  Token balance in the asset pool + token balance in the locked asset pool
     * @param ethToBuy_  Amount of ETH to spend
     * 
     */
    function calculatePurchaseReturn(uint256 ethReserve_, uint256 tokenReserve_, uint256 ethToBuy_) external view returns (uint256) {
        if (ethToBuy_ == 0) {
            return 0;
        }
        tokenReserve_ += VIRTUAL_TOKEN_LOCKED;
        ethReserve_ += VIRTUAL_ETH_RESERVE;
        uint256 tokensToBuy = tokenReserve_ - K / (ethReserve_ + ethToBuy_);
        return tokensToBuy;
    }

    /** v2
     * @dev Calculate the amount of ETH that can be obtained by selling a specified amount of tokens
     * @param ethReserve_  ETH balance in the asset pool
     * @param tokenReserve_  Token balance in the asset pool + token balance in the locked asset pool
     * @param tokenToSell_  Amount of tokens to sell
     * 
     */
    function calculateSaleReturn(uint256 ethReserve_, uint256 tokenReserve_, uint256 tokenToSell_) external view returns (uint256) {
        if (tokenToSell_ == 0) {
            return 0;
        }
        tokenReserve_ += VIRTUAL_TOKEN_LOCKED;
        ethReserve_ += VIRTUAL_ETH_RESERVE;
        uint256 ethToReturn = ethReserve_ - (K / (tokenReserve_ + tokenToSell_));
        return ethToReturn;
    }

    // v2
    function getTokenPrice(uint256 ethReserve_) external view returns (uint256) {
        ethReserve_ += VIRTUAL_ETH_RESERVE;
        return (ethReserve_ ** 2 * PRICE_PRECISION) / K;
    }

}
