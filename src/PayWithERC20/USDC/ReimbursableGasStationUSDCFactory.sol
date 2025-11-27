// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ReimbursableGasStationUSDC} from "./ReimbursableGasStationUSDC.sol";

contract ReimbursableGasStationUSDCFactory {
    address public immutable PRICE_FEED;
    address public immutable REIMBURSEMENT_ERC20;
    address public immutable TK_GAS_DELEGATE;

    constructor(address _priceFeed, address _reimbursementERC20, address _tkGasDelegate) {
        PRICE_FEED = _priceFeed;
        REIMBURSEMENT_ERC20 = _reimbursementERC20;
        TK_GAS_DELEGATE = _tkGasDelegate;
    }

    function createReimbursableGasStation(
        bytes32 _salt,
        address _reimbursementAddress,
        uint16 _gasFeeBasisPoints,
        uint256 _baseGasFeeWei,
        uint256 _baseGasFeeERC20,
        uint256 _maxDepositLimitERC20,
        uint256 _minimumTransactionGasLimitWei
    ) external returns (address) {
        return address(
            new ReimbursableGasStationUSDC{salt: _salt}(
                PRICE_FEED,
                TK_GAS_DELEGATE,
                _reimbursementAddress,
                REIMBURSEMENT_ERC20,
                _gasFeeBasisPoints,
                _baseGasFeeWei,
                _baseGasFeeERC20,
                _maxDepositLimitERC20,
                _minimumTransactionGasLimitWei
            )
        );
    }
}
