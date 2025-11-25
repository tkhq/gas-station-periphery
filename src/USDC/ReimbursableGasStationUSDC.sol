// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AbstractReimbursableGasStation} from "../AbstractReimbursableGasStation.sol";
import {AggregatorV3Interface} from
    "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract ReimbursableGasStationUSDC is AbstractReimbursableGasStation {
    error InvalidPrice();

    AggregatorV3Interface internal priceFeed;
    uint8 public immutable PRICE_FEED_DECIMALS;
    uint8 public immutable USDC_DECIMALS;
    uint256 public immutable TEN_TO_USDC_DECIMALS;
    uint256 public immutable TEN_TO_18_PLUS_PRICE_FEED_DECIMALS;

    constructor(
        address _priceFeed,
        address _tkGasDelegate,
        address _reimbursementAddress,
        address _reimbursementErc20,
        uint16 _gasFeeBasisPoints,
        uint256 _minimumGasFee,
        uint256 _maxGasLimit
    )
        AbstractReimbursableGasStation(
            _tkGasDelegate,
            _reimbursementAddress,
            _reimbursementErc20,
            _gasFeeBasisPoints,
            _minimumGasFee,
            _maxGasLimit
        )
    {
        priceFeed = AggregatorV3Interface(_priceFeed);
        PRICE_FEED_DECIMALS = priceFeed.decimals();
        USDC_DECIMALS = 6;
        TEN_TO_USDC_DECIMALS = 10 ** USDC_DECIMALS;
        TEN_TO_18_PLUS_PRICE_FEED_DECIMALS = 10 ** 18 * (10 ** PRICE_FEED_DECIMALS);
    }

    function _convertGasToERC20(uint256 _gasAmount) internal override returns (uint256) {
        uint256 gasCostWei = _gasAmount * tx.gasprice;

        uint256 price = _getUSDCPrice();

        uint256 usdcCost = (gasCostWei * price * TEN_TO_USDC_DECIMALS) / TEN_TO_18_PLUS_PRICE_FEED_DECIMALS;
        return usdcCost;
    }

    function _getUSDCPrice() internal view returns (uint256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price);
    }
}
