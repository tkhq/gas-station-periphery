// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {TKBundledGasStation} from "../../src/BundledGasStation/TKBundledGasStation.sol";

/// @notice Deploy script for TKBundledGasStation
contract DeployTKBundledGasStation is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // TK Gas Delegate address (same across all networks)
        address tkGasDelegate = 0x000066a00056CD44008768E2aF00696e19A30084;

        vm.startBroadcast(deployerPrivateKey);

        TKBundledGasStation bundledGasStation = new TKBundledGasStation(tkGasDelegate);

        console2.log("TKBundledGasStation deployed at:", address(bundledGasStation));
        console2.log("TK Gas Delegate:", tkGasDelegate);

        vm.stopBroadcast();
    }
}

