// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AbstractReimbursableGasStation} from "../AbstractReimbursableGasStation.sol";
import {AggregatorV3Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract ReimbursableGasStationUSDC is AbstractReimbursableGasStation {
    error InvalidPrice();
    error InvalidFeePercentage();

    AggregatorV3Interface internal priceFeed;
    uint8 public immutable FEE_PERCENTAGE;

    constructor(address _priceFeed, uint8 _feePercentage, address _tkGasDelegate, address _reimbursementAddress, address _reimbursementErc20) AbstractReimbursableGasStation(_tkGasDelegate, _reimbursementAddress, _reimbursementErc20) {
        priceFeed = AggregatorV3Interface(_priceFeed);
        if (_feePercentage > 100) {
            revert InvalidFeePercentage();
        }
        FEE_PERCENTAGE = _feePercentage;
    }

    function _gasToReimburseInERC20(uint256 _gasAmount, bool _returns) internal override returns (uint256) {
        uint256 modifiedGasAmount = _gasAmount + (_returns ? 100 : 0) + 9000; 
        modifiedGasAmount += modifiedGasAmount * FEE_PERCENTAGE / 100; 
        // 9000 is the gas cost of calling chainlink and internal functions
        // 100 is the the extra permium of having a return value 

        uint256 price = _getUSDCPrice();
        if (price == 0) {
            revert InvalidPrice();
        }
        uint256 usdcCost = ((modifiedGasAmount * tx.gasprice * price) / 1e18) / 100; 
        return usdcCost;
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