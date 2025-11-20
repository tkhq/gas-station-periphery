// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ReimbursableGasStationUSDC} from "./ReimbursableGasStationUSDC.sol";

contract ReimbursableGasStationUSDCFactory {
    address public immutable PRICE_FEED;
    address public immutable REIMBURSEMENT_ERC20;
    address public immutable TK_GAS_DELEGATE;
    uint16 public immutable GAS_FEE_BASIS_POINTS;
    uint256 public immutable BASE_GAS_FEE;

    constructor(address _priceFeed, address _reimbursementErc20, address _tkGasDelegate, uint16 _gasFeeBasisPoints, uint256 _baseGasFee) {
        PRICE_FEED = _priceFeed;
        REIMBURSEMENT_ERC20 = _reimbursementErc20;
        TK_GAS_DELEGATE = _tkGasDelegate;
        GAS_FEE_BASIS_POINTS = _gasFeeBasisPoints;
        BASE_GAS_FEE = _baseGasFee;
    }

    function createReimbursableGasStation(
        bytes32 _salt,
        uint16 _feePercentage,
        address _reimbursementAddress
    ) external returns (address instance) {
        instance = address(
            new ReimbursableGasStationUSDC{salt: _salt}(PRICE_FEED, _feePercentage, TK_GAS_DELEGATE, _reimbursementAddress, REIMBURSEMENT_ERC20, GAS_FEE_BASIS_POINTS, BASE_GAS_FEE)
        );
        return instance;
    }
}

