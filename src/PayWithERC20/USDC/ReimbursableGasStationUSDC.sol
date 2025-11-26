// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ReimbursableGasStationAggregatorV3Oracle} from "../ReimbursableGasStationAggregatorV3Oracle.sol";

contract ReimbursableGasStationUSDC is ReimbursableGasStationAggregatorV3Oracle {
    constructor(
        address _priceFeed,
        address _tkGasDelegate,
        address _reimbursementAddress,
        address _reimbursementErc20,
        uint16 _gasFeeBasisPoints,
        uint256 _minimumGasFee,
        uint256 _maxDepositLimit,
        uint256 _minimumTransactionGasLimitWei
    )
        ReimbursableGasStationAggregatorV3Oracle(
            _priceFeed,
            _tkGasDelegate,
            _reimbursementAddress,
            _reimbursementErc20,
            6, // USDC decimals
            _gasFeeBasisPoints,
            false, // USDC always uses false for _erc20TransferSucceededReturnDataCheck
            _minimumGasFee,
            _maxDepositLimit,
            _minimumTransactionGasLimitWei
        )
    {}
}
