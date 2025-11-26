// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AbstractReimbursableGasStation} from "./AbstractReimbursableGasStation.sol";
import {AggregatorV3Interface} from
    "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract ReimbursableGasStationAggregatorV3Oracle is AbstractReimbursableGasStation {
    error InvalidPrice();

    AggregatorV3Interface internal priceFeed;
    uint8 public immutable PRICE_FEED_DECIMALS;
    uint8 public immutable REIMBURSEMENT_TOKEN_DECIMALS;
    uint256 public immutable TEN_TO_REIMBURSEMENT_TOKEN_DECIMALS;
    uint256 public immutable TEN_TO_18_PLUS_PRICE_FEED_DECIMALS;

    constructor(
        address _priceFeed,
        address _tkGasDelegate,
        address _reimbursementAddress,
        address _reimbursementErc20,
        uint8 _reimbursementTokenDecimals,
        uint16 _gasFeeBasisPoints,
        bool _erc20TransferSucceededReturnDataCheck,
        uint256 _minimumGasFee,
        uint256 _maxDepositLimit,
        uint256 _minimumTransactionGasLimitWei
    )
        AbstractReimbursableGasStation(
            _tkGasDelegate,
            _reimbursementAddress,
            _reimbursementErc20,
            _gasFeeBasisPoints,
            _erc20TransferSucceededReturnDataCheck,
            _minimumGasFee,
            _maxDepositLimit,
            _minimumTransactionGasLimitWei
        )
    {
        priceFeed = AggregatorV3Interface(_priceFeed);
        PRICE_FEED_DECIMALS = priceFeed.decimals();
        REIMBURSEMENT_TOKEN_DECIMALS = _reimbursementTokenDecimals;
        TEN_TO_REIMBURSEMENT_TOKEN_DECIMALS = 10 ** _reimbursementTokenDecimals;
        TEN_TO_18_PLUS_PRICE_FEED_DECIMALS = 10 ** 18 * (10 ** PRICE_FEED_DECIMALS);
    }

    function _convertGasToERC20(uint256 _gasAmount) internal view override returns (uint256) {
        uint256 gasCostWei = _gasAmount * tx.gasprice;

        uint256 price = _getPrice();

        uint256 tokenCost =
            (gasCostWei * price * TEN_TO_REIMBURSEMENT_TOKEN_DECIMALS) / TEN_TO_18_PLUS_PRICE_FEED_DECIMALS;
        return tokenCost;
    }

    function _getPrice() internal view returns (uint256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price);
    }
}
