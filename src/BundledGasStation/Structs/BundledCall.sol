// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;


struct BundleCall {
    address target;
    uint256 gasLimit;
    bytes data; // completely arbitrary data sent to the target, could call the fallback function or anything else
}