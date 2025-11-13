// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ReimbursableGasStationUSDC} from "./ReimbursableGasStationUSDC.sol";

contract ReimbursableGasStationUSDCFactory {
    address public immutable PRICE_FEED;

    constructor(address _priceFeed) {
        PRICE_FEED = _priceFeed;
    }

    function createReimbursableGasStation(
        bytes32 _salt,
        uint8 _feePercentage,
        address _tkGasDelegate,
        address _reimbursementAddress,
        address _reimbursementErc20
    ) external returns (address instance) {
        instance = address(
            new ReimbursableGasStationUSDC{salt: _salt}(PRICE_FEED, _feePercentage, _tkGasDelegate, _reimbursementAddress, _reimbursementErc20)
        );
        return instance;
    }
}

