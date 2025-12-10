// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

struct BundleExecute {
    // For use with the execute functions only
    address target;
    uint256 gasLimit;
    address to;
    uint256 value;
    bytes data;
}