// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AbstractReimbursableGasStation} from "../AbstractReimbursableGasStation.sol";
import {AggregatorV3Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract ReimbursableGasStationUSDC is AbstractReimbursableGasStation {
    error InvalidPrice();
    error InvalidFeePercentage();

    AggregatorV3Interface internal priceFeed;
    uint16 public immutable FEE_PERCENTAGE;
    uint8 public immutable PRICE_FEED_DECIMALS;
    uint8 public immutable USDC_DECIMALS;
    uint256 public immutable TEN_TO_USDC_DECIMALS;
    uint256 public immutable TEN_TO_18_PLUS_PRICE_FEED_DECIMALS;

    bytes32 private constant _TRANSIENT_GAS_PRICE_SLOT = bytes32(uint256(keccak256("gas-station.reimbursable-gas-station-usdc.gas-price")) - 1);

    constructor(address _priceFeed, uint16 _feePercentage, address _tkGasDelegate, address _reimbursementAddress, address _reimbursementErc20, uint16 _gasFeeBasisPoints, uint256 _minimumGasFee) AbstractReimbursableGasStation(_tkGasDelegate, _reimbursementAddress, _reimbursementErc20, _gasFeeBasisPoints, _minimumGasFee) {
        priceFeed = AggregatorV3Interface(_priceFeed);
        if (_feePercentage > 10000) {
            revert InvalidFeePercentage();
        }
        FEE_PERCENTAGE = _feePercentage;
        PRICE_FEED_DECIMALS = priceFeed.decimals();
        USDC_DECIMALS = 6;
        TEN_TO_USDC_DECIMALS = 10 ** USDC_DECIMALS;
        TEN_TO_18_PLUS_PRICE_FEED_DECIMALS = 10 ** 18 * (10 ** PRICE_FEED_DECIMALS);
    }

    function _convertGasToERC20(uint256 _gasAmount) internal override returns (uint256) {
    
    }

    function _getUSDCPrice() internal view returns (uint256) {
         (
            ,
            int256 price,
            ,
            ,
        ) = priceFeed.latestRoundData();
        return uint256(price);
    }
}