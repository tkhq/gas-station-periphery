// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {ReimbursableGasStationUSDCFactory} from "../src/USDC/ReimbursableGasStationUSDCFactory.sol";

contract BaseDeployReimbursableGasStationUSDCFactory is Script {
    // Base mainnet USDC/USD price feed
    address private constant PRICE_FEED = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address private constant REIMBURSEMENT_ERC20 = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address private constant TK_GAS_DELEGATE = 0x000066a00056CD44008768E2aF00696e19A30084;
    uint16 private constant GAS_FEE_BASIS_POINTS = 100; // 1% (100 basis points)
    uint256 private constant BASE_GAS_FEE_ERC20 = 21000; // Base gas fee
    uint256 private constant MAX_GAS_LIMIT_ERC20 = 10_000_000_000; // Max gas limit in ERC20 tokens (10k USDC with 6 decimals)

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        ReimbursableGasStationUSDCFactory factory = new ReimbursableGasStationUSDCFactory(
            PRICE_FEED, REIMBURSEMENT_ERC20, TK_GAS_DELEGATE, GAS_FEE_BASIS_POINTS, BASE_GAS_FEE_ERC20, MAX_GAS_LIMIT_ERC20
        );

        console2.log("ReimbursableGasStationUSDCFactory deployed at:", address(factory));
        console2.log("Price Feed:", PRICE_FEED);

        vm.stopBroadcast();
    }
}
