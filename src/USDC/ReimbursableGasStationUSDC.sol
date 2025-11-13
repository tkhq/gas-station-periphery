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

    constructor(address _priceFeed, uint16 _feePercentage, address _tkGasDelegate, address _reimbursementAddress, address _reimbursementErc20) AbstractReimbursableGasStation(_tkGasDelegate, _reimbursementAddress, _reimbursementErc20) {
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

    function _gasToReimburseInERC20(uint256 _gasAmount, bool _returns) internal override returns (uint256) {
        uint256 modifiedGasAmount = _gasAmount + (_returns ? 100 : 0) + 26000; 
        // 100 is the the extra permium of having a return value (estimated)
        // 26000 is the premium of the internal functions (estimated) + a transferfrom (estimated)
        uint256 gasBefore = gasleft();
        uint256 price = _getUSDCPrice();
        if (price == 0) {
            revert InvalidPrice();
        }
        uint256 gasUsedForOracle = gasBefore - gasleft();
        modifiedGasAmount += gasUsedForOracle;
        modifiedGasAmount += modifiedGasAmount * FEE_PERCENTAGE / 10000; 
        uint256 gasCostWei = modifiedGasAmount * tx.gasprice;
        
        uint256 usdcCost = (gasCostWei * price * TEN_TO_USDC_DECIMALS) / TEN_TO_18_PLUS_PRICE_FEED_DECIMALS;
        
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