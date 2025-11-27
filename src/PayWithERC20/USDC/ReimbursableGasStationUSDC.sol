// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ReimbursableGasStationAggregatorV3Oracle} from "../ReimbursableGasStationAggregatorV3Oracle.sol";

contract ReimbursableGasStationUSDC is ReimbursableGasStationAggregatorV3Oracle {
    constructor(
        address _priceFeed,
        address _tkGasDelegate,
        address _reimbursementAddress,
        address _reimbursementERC20,
        uint16 _gasFeeBasisPoints,
        uint256 _baseGasFeeWei,
        uint256 _baseGasFeeERC20,
        uint256 _maxDepositLimitERC20,
        uint256 _minimumTransactionGasLimitWei
    )
        ReimbursableGasStationAggregatorV3Oracle(
            _priceFeed,
            _tkGasDelegate,
            _reimbursementAddress,
            _reimbursementERC20,
            6, // USDC decimals
            _gasFeeBasisPoints,
            false, // USDC always uses false for _ERC20TransferSucceededReturnDataCheck
            _baseGasFeeWei,
            _baseGasFeeERC20,
            _maxDepositLimitERC20,
            _minimumTransactionGasLimitWei
        )
    {}
}
